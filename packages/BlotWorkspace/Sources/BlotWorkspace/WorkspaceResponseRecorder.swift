import BlotDomain
import Foundation

/// Every published delta is durable first. Recovery never starts a model request.
public struct WorkspaceResponseRecorder: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func begin(id: UUID, replyingTo source: BlotV3.Message, agentID: UUID?, now: Date = Date()) async throws -> BlotV3.Message {
        struct Input: Encodable { let sourceID: UUID; let agentID: UUID? }
        let command = try WorkspaceCommand(type: "response.begin", workspaceID: identity.workspaceID,
            payload: Input(sourceID: source.metadata.id, agentID: agentID)).data()
        _ = try await repository.execute(commandID: id, command: command, identity: identity) { tx in
            let saved = try tx.require(BlotV3.Message.self, id: source.metadata.id)
            guard saved.role == .user else { throw WorkspaceStorageError.invalidRecord }
            _ = try tx.require(BlotV3.Conversation.self, id: saved.conversationId)
            if let agentID { _ = try tx.require(BlotV3.AgentProfile.self, id: agentID) }
            let response = try BlotV3.Message(metadata: tx.metadata(id: id, now: now), conversationId: saved.conversationId,
                role: .assistant, content: "", delivery: .running, commandId: saved.commandId, artifactIds: [],
                authorAgentId: agentID, replyToMessageId: saved.metadata.id, mentions: [], position: tx.nextMessagePosition(in: saved.conversationId),
                executorDeviceId: tx.identity.deviceID)
            try tx.put(response, expectedVersion: 0)
            return id
        }
        return try await requireResponse(id)
    }

    public func append(_ text: String, to id: UUID, now: Date = Date()) async throws -> BlotV3.Message {
        struct Input: Encodable { let responseID: UUID; let text: String }
        let command = try WorkspaceCommand(type: "response.append", workspaceID: identity.workspaceID, payload: Input(responseID: id, text: text)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let message = try tx.require(BlotV3.Message.self, id: id)
            guard message.executorDeviceId == tx.identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
            guard message.role == .assistant, message.delivery == .running else { throw WorkspaceStorageError.invalidRecord }
            try Self.replace(tx, message, content: message.content + text, delivery: .running, now: now)
            return id
        }
        return try await requireResponse(id)
    }

    public func finish(_ id: UUID, delivery: BlotV3.DeliveryState, now: Date = Date()) async throws -> BlotV3.Message {
        struct Input: Encodable { let responseID: UUID; let delivery: BlotV3.DeliveryState }
        let command = try WorkspaceCommand(type: "response.finish", workspaceID: identity.workspaceID,
            payload: Input(responseID: id, delivery: delivery)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let message = try tx.require(BlotV3.Message.self, id: id)
            guard message.executorDeviceId == tx.identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
            guard [.completed, .interrupted, .canceled, .failed].contains(delivery), message.role == .assistant else { throw WorkspaceStorageError.invalidRecord }
            if message.delivery == delivery { return id }
            guard message.delivery == .running else { throw WorkspaceStorageError.invalidRecord }
            try Self.replace(tx, message, content: message.content, delivery: delivery, now: now)
            return id
        }
        return try await requireResponse(id)
    }

    public func recoverInterruptedResponses(now: Date = Date()) async throws {
        let messages = try await repository.records(BlotV3.Message.self, workspaceID: identity.workspaceID)
        guard messages.contains(where: { $0.role == .assistant && $0.delivery == .running && $0.executorDeviceId == identity.deviceID }) else { return }
        struct Input: Encodable { let deviceID: UUID }
        let command = try WorkspaceCommand(type: "response.recover", workspaceID: identity.workspaceID, payload: Input(deviceID: identity.deviceID)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            for message in try tx.records(BlotV3.Message.self) where message.role == .assistant && message.delivery == .running && message.executorDeviceId == tx.identity.deviceID {
                try Self.replace(tx, message, content: message.content, delivery: .interrupted, now: now)
            }
            return tx.identity.workspaceID
        }
    }

    private func requireResponse(_ id: UUID) async throws -> BlotV3.Message {
        guard let response = try await repository.record(BlotV3.Message.self, id: id, workspaceID: identity.workspaceID) else { throw WorkspaceStorageError.missingRecord }
        return response
    }

    private static func replace(_ tx: WorkspaceTransaction, _ message: BlotV3.Message, content: String, delivery: BlotV3.DeliveryState, now: Date) throws {
        _ = try tx.require(BlotV3.Conversation.self, id: message.conversationId)
        let updated = try BlotV3.Message(metadata: tx.metadata(id: message.metadata.id, now: now, replacing: message.metadata),
            conversationId: message.conversationId, role: message.role, content: content, delivery: delivery, commandId: message.commandId,
            artifactIds: message.artifactIds, authorAgentId: message.authorAgentId, replyToMessageId: message.replyToMessageId,
            mentions: message.mentions, position: message.position, executorDeviceId: message.executorDeviceId)
        try tx.put(updated, expectedVersion: message.metadata.version)
    }
}
