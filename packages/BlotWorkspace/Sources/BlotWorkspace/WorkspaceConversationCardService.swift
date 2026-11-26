import BlotDomain
import Foundation

/// Atomic, versioned interaction records. Answering never executes the bound external operation.
public struct WorkspaceConversationCardService: Sendable {
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    @discardableResult
    public func create(id: UUID, sourceMessageID: UUID, operationID: UUID, agentID: UUID?, content: WorkspaceCardContent,
                       expiresAt: Date = Date().addingTimeInterval(600), now: Date = Date()) async throws -> UUID {
        try content.validate()
        guard expiresAt > now, expiresAt.timeIntervalSince(now) <= 86_400 else { throw WorkspaceStorageError.invalidParameters }
        struct Input: Encodable { let source: UUID; let operation: UUID; let content: WorkspaceCardContent }
        let command = try WorkspaceCommand(type: "card.create", workspaceID: identity.workspaceID,
            payload: Input(source: sourceMessageID, operation: operationID, content: content)).data()
        return try await repository.execute(commandID: id, command: command, identity: identity) { tx in
            let source = try tx.require(BlotV3.Message.self, id: sourceMessageID)
            let messageID = WorkspaceLogicalID.make(kind: "CardMessage", workspaceID: tx.identity.workspaceID, parts: [id.uuidString])
            let message = try BlotV3.Message(metadata: tx.metadata(id: messageID, now: now), conversationId: source.conversationId,
                role: .assistant, content: content.fallback, delivery: .completed, commandId: id, artifactIds: [],
                authorAgentId: agentID, replyToMessageId: sourceMessageID, position: tx.nextMessagePosition(in: source.conversationId),
                executorDeviceId: tx.identity.deviceID)
            let card = try BlotV3.ConversationCard(metadata: tx.metadata(id: id, now: now), messageId: messageID,
                operationId: operationID, executorDeviceId: tx.identity.deviceID, kind: content.kind, state: "pending",
                expiresAt: expiresAt, payloadJSON: String(decoding: JSONEncoder().encode(content), as: UTF8.self), updatedByDeviceId: tx.identity.deviceID)
            try tx.put(message, expectedVersion: 0); try tx.put(card, expectedVersion: 0)
            // Pending replies reserve ordering before the tool runs. Their eventual report follows the interaction.
            for pending in try tx.records(BlotV3.Message.self) where pending.conversationId == source.conversationId && pending.role == .assistant && pending.delivery == .running && pending.replyToMessageId == sourceMessageID && pending.authorAgentId == agentID && pending.executorDeviceId == tx.identity.deviceID {
                let moved = try BlotV3.Message(metadata: tx.metadata(id: pending.metadata.id, now: now, replacing: pending.metadata),
                    conversationId: pending.conversationId, role: pending.role, content: pending.content, delivery: pending.delivery,
                    commandId: pending.commandId, artifactIds: pending.artifactIds, authorAgentId: pending.authorAgentId,
                    replyToMessageId: pending.replyToMessageId, mentions: pending.mentions, position: tx.nextMessagePosition(in: source.conversationId), executorDeviceId: pending.executorDeviceId)
                try tx.put(moved, expectedVersion: pending.metadata.version)
            }
            return id
        }
    }

    public func respond(commandID: UUID, cardID: UUID, expectedVersion: Int, response: WorkspaceCardResponse, now: Date = Date()) async throws {
        struct Input: Encodable { let id: UUID; let version: Int; let response: WorkspaceCardResponse }
        let command = try WorkspaceCommand(type: "card.respond", workspaceID: identity.workspaceID,
            payload: Input(id: cardID, version: expectedVersion, response: response)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let old = try tx.require(BlotV3.ConversationCard.self, id: cardID, version: expectedVersion)
            try tx.requireResolved(kind: BlotV3.ConversationCard.recordKind, id: cardID)
            guard old.state == "pending", old.expiresAt.map({ $0 > now }) ?? true else { throw WorkspaceStorageError.permissionDenied }
            let content = try JSONDecoder().decode(WorkspaceCardContent.self, from: Data(old.payloadJSON.utf8))
            try Self.validate(response, for: content)
            let card = try BlotV3.ConversationCard(metadata: tx.metadata(id: cardID, now: now, replacing: old.metadata),
                messageId: old.messageId, operationId: old.operationId, executorDeviceId: old.executorDeviceId, kind: old.kind,
                state: "answered", expiresAt: old.expiresAt, payloadJSON: old.payloadJSON,
                responseJSON: String(decoding: JSONEncoder().encode(response), as: UTF8.self), updatedByDeviceId: tx.identity.deviceID)
            try tx.put(card, expectedVersion: expectedVersion)
            return cardID
        }
    }

    public func waitForResponse(cardID: UUID) async throws -> WorkspaceCardResponse {
        guard let initial = try await repository.record(BlotV3.ConversationCard.self, id: cardID, workspaceID: identity.workspaceID),
              initial.metadata.ownerId == identity.ownerID, initial.executorDeviceId == identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
        if initial.responseJSON != nil { return try await consume(cardID: cardID) }
        let deadline = initial.expiresAt ?? Date().addingTimeInterval(600)
        return try await withThrowingTaskGroup(of: WorkspaceCardResponse.self) { group in
            group.addTask {
                for await _ in await repository.changes() {
                    try _Concurrency.Task.checkCancellation()
                    guard let card = try await repository.record(BlotV3.ConversationCard.self, id: cardID, workspaceID: identity.workspaceID),
                          card.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.missingRecord }
                    if card.responseJSON != nil { return try await consume(cardID: cardID) }
                }
                throw CancellationError()
            }
            group.addTask {
                try await _Concurrency.Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                throw WorkspaceStorageError.permissionDenied
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else { throw CancellationError() }
            return response
        }
    }

    private func consume(cardID: UUID) async throws -> WorkspaceCardResponse {
        _ = try await repository.execute(commandID: UUID(), command: Data(("card.consume:" + cardID.uuidString).utf8), identity: identity) { tx in
            let old = try tx.require(BlotV3.ConversationCard.self, id: cardID)
            guard old.executorDeviceId == tx.identity.deviceID, let raw = old.responseJSON else { throw WorkspaceStorageError.permissionDenied }
            if old.state == "consumed" { return cardID }
            guard old.state == "answered" else { throw WorkspaceStorageError.permissionDenied }
            let card = try BlotV3.ConversationCard(metadata: tx.metadata(id: cardID, now: Date(), replacing: old.metadata),
                messageId: old.messageId, operationId: old.operationId, executorDeviceId: old.executorDeviceId, kind: old.kind,
                state: "consumed", expiresAt: old.expiresAt, payloadJSON: old.payloadJSON, responseJSON: raw, updatedByDeviceId: tx.identity.deviceID)
            try tx.put(card, expectedVersion: old.metadata.version)
            let response = try JSONDecoder().decode(WorkspaceCardResponse.self, from: Data(raw.utf8))
            let content = try JSONDecoder().decode(WorkspaceCardContent.self, from: Data(old.payloadJSON.utf8))
            if case .question(let question) = content, let answer = response.value {
                let message = try tx.require(BlotV3.Message.self, id: old.messageId)
                let answered = try BlotV3.Message(metadata: tx.metadata(id: message.metadata.id, now: Date(), replacing: message.metadata),
                    conversationId: message.conversationId, role: message.role, content: question.prompt + "\n" + answer,
                    delivery: message.delivery, commandId: message.commandId, artifactIds: message.artifactIds,
                    authorAgentId: message.authorAgentId, replyToMessageId: message.replyToMessageId, mentions: message.mentions,
                    position: message.position, executorDeviceId: message.executorDeviceId)
                try tx.put(answered, expectedVersion: message.metadata.version)
            }
            return cardID
        }
        guard let card = try await repository.record(BlotV3.ConversationCard.self, id: cardID, workspaceID: identity.workspaceID),
              let raw = card.responseJSON else { throw WorkspaceStorageError.missingRecord }
        return try JSONDecoder().decode(WorkspaceCardResponse.self, from: Data(raw.utf8))
    }

    /// The existing permission service still validates the action digest and claims the invocation.
    public func review(action: BlotV3.PreparedAction, context: WorkspaceToolContext, title: String, details: String) async throws -> Bool {
        try await review(action: action, context: context, content: .command(.init(title: title, details: details, command: action.parameters))).action == "allow"
    }

    public func review(action: BlotV3.PreparedAction, context: WorkspaceToolContext, content: WorkspaceCardContent) async throws -> WorkspaceCardResponse {
        let id = WorkspaceLogicalID.make(kind: "ActionCard", workspaceID: identity.workspaceID, parts: [action.metadata.id.uuidString, action.preparationId?.uuidString ?? action.digest])
        try await create(id: id, sourceMessageID: context.sourceMessageID, operationID: action.metadata.id, agentID: context.agentID,
            content: content, expiresAt: action.expiresAt)
        return try await waitForResponse(cardID: id)
    }

    /// A distinct action makes older executors fail closed instead of copying the full list.
    static func selectedCookieDomains(_ response: WorkspaceCardResponse, transfer: WorkspaceCardContent.CookieTransfer) throws -> [String] {
        if response.action == "allow", response.value == nil { return transfer.domains }
        guard response.action == "allow_domains", let raw = response.value,
              let domains = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)),
              !domains.isEmpty, domains.count == Set(domains).count,
              Set(domains).isSubset(of: Set(transfer.domains)) else { throw WorkspaceStorageError.invalidParameters }
        return domains
    }

    static func validate(_ response: WorkspaceCardResponse, for content: WorkspaceCardContent) throws {
        guard (response.value?.utf8.count ?? 0) <= 48 * 1024 else { throw WorkspaceStorageError.invalidParameters }
        let allowed: Set<String>
        switch content {
        case .question(let question):
            if response.action == "dismiss", response.value == nil { return }
            guard response.action == "submit", let answer = response.value, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  question.allowsCustomAnswer || question.choices.contains(answer) else { throw WorkspaceStorageError.invalidParameters }
            return
        case .command(let command): allowed = command.ruleScope == nil ? ["allow", "deny"] : ["allow", "allow_rule", "deny"]
        case .email:
            guard ["send", "discard"].contains(response.action) else { throw WorkspaceStorageError.invalidParameters }
            if response.action == "send" {
                guard let raw = response.value else { throw WorkspaceStorageError.invalidParameters }
                let draft = try JSONDecoder().decode(WorkspaceCardContent.MailDraft.self, from: Data(raw.utf8))
                guard !draft.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceStorageError.invalidParameters }
            } else if response.value != nil { throw WorkspaceStorageError.invalidParameters }
            return
        case .slack:
            guard ["send", "discard"].contains(response.action), response.action != "send" || response.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw WorkspaceStorageError.invalidParameters }
            return
        case .purchase: allowed = ["allow", "deny"]
        case .takeover: allowed = ["done", "skip"]
        case .cookies(let transfer):
            if response.action == "allow_domains" {
                _ = try Self.selectedCookieDomains(response, transfer: transfer)
                return
            }
            allowed = ["allow", "deny"]
        case .mailFailure: allowed = ["dismiss", "confirmed_sent", "confirmed_not_sent"]
        case .credential: allowed = ["saved", "dismiss"] // Secret values go directly to the executor's Keychain.
        case .connectionRequest: allowed = ["connected", "dismiss"] // The tool independently verifies the actual connection.
        case .subscription, .task, .plugin, .page: allowed = ["dismiss"]
        }
        guard allowed.contains(response.action), response.value == nil else { throw WorkspaceStorageError.invalidParameters }
    }
}
