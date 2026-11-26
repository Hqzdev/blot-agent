import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

@MainActor
protocol WorkspaceCardCommands {
    func retryMailCard(_ id: UUID) async throws
    func respondToCard(_ id: UUID, version: Int, response: WorkspaceCardResponse) async throws
    func saveCardSecret(_ id: UUID, version: Int, secret: String) async throws
}

extension LocalWorkspaceService: WorkspaceCardCommands {
    func retryMailCard(_ id: UUID) async throws {
        let identity = try await context()
        guard cardWorkers[id] == nil,
              let card = try await repository.record(BlotV3.ConversationCard.self, id: id, workspaceID: identity.workspaceID),
              card.metadata.ownerId == identity.ownerID, card.kind == "mailFailure", card.executorDeviceId == identity.deviceID,
              let raw = card.responseJSON, try JSONDecoder().decode(WorkspaceCardResponse.self, from: Data(raw.utf8)).action == "confirmed_not_sent",
              let action = try await repository.record(BlotV3.PreparedAction.self, id: card.operationId, workspaceID: identity.workspaceID), action.state == .failed,
              let message = try await repository.record(BlotV3.Message.self, id: card.messageId, workspaceID: identity.workspaceID),
              let source = message.replyToMessageId, let agentID = message.authorAgentId else { throw WorkspaceStorageError.permissionDenied }
        let saved = try JSONDecoder().decode(ChatJSON.self, from: Data(action.parameters.utf8))
        let arguments: ChatJSON
        if case .object(let values) = saved, let original = values["arguments"], values["review"] != nil { arguments = original } else { arguments = saved }
        let provider = AppleToolProvider(repository: repository, identity: identity, controller: appleIntegrations)
        let toolContext = WorkspaceToolContext(sourceMessageID: source, taskID: nil, allowedToolIDs: [action.toolId], agentID: agentID, inlineCards: true)
        let worker = _Concurrency.Task<Void, Error> {
            _ = try await provider.execute(.init(id: "mail-retry:" + id.uuidString, name: action.toolId, arguments: arguments), context: toolContext)
        }
        cardWorkers[id] = worker
        defer { cardWorkers[id] = nil }
        try await worker.value
    }
    func respondToCard(_ id: UUID, version: Int, response: WorkspaceCardResponse) async throws {
        let identity = try await context()
        let now = Date()
        if ["confirmed_sent", "confirmed_not_sent"].contains(response.action) {
            guard let card = try await repository.record(BlotV3.ConversationCard.self, id: id, workspaceID: identity.workspaceID),
                  card.kind == "mailFailure", card.state == "pending", card.metadata.version == version, card.expiresAt.map({ $0 > now }) ?? true,
                  card.metadata.ownerId == identity.ownerID, card.executorDeviceId == identity.deviceID,
                  let invocation = try await repository.projection(identity: identity).invocations.first(where: { $0.preparedActionId == card.operationId && $0.state == .unknown }) else { throw WorkspaceStorageError.permissionDenied }
            _ = try await resolveAppleInvocation(invocation.metadata.id, succeeded: response.action == "confirmed_sent")
        }
        if response.action == "saved" {
            guard let card = try await repository.record(BlotV3.ConversationCard.self, id: id, workspaceID: identity.workspaceID),
                  card.executorDeviceId == identity.deviceID, let value = try await mcpCredentials.read("card:" + identity.ownerID.uuidString + ":" + id.uuidString), !value.isEmpty else { throw WorkspaceStorageError.permissionDenied }
        }
        try await WorkspaceConversationCardService(repository: repository, identity: identity).respond(
            commandID: UUID(), cardID: id, expectedVersion: version, response: response, now: now)
    }
    func saveCardSecret(_ id: UUID, version: Int, secret: String) async throws {
        let identity = try await context()
        guard !secret.isEmpty, secret.utf8.count <= 16 * 1024,
              let card = try await repository.record(BlotV3.ConversationCard.self, id: id, workspaceID: identity.workspaceID),
              card.metadata.ownerId == identity.ownerID, card.metadata.version == version,
              card.executorDeviceId == identity.deviceID, card.state == "pending", card.expiresAt.map({ $0 > Date() }) ?? true,
              case .credential(let request) = try JSONDecoder().decode(WorkspaceCardContent.self, from: Data(card.payloadJSON.utf8)),
              request.reference == "card:" + identity.ownerID.uuidString + ":" + id.uuidString else { throw WorkspaceStorageError.permissionDenied }
        // Do not pass this value through WorkspaceRequest, a response record, or the model context.
        try await mcpCredentials.write(Data(secret.utf8), name: request.reference)
        do { try await respondToCard(id, version: version, response: .init(action: "saved")) }
        catch { try? await mcpCredentials.remove(request.reference); throw error }
    }
}

@MainActor
protocol WorkspaceSubscriptionCardCommands {
    func refreshSubscriptionCard(_ id: UUID) async throws
}

extension WorkspaceAccountApplicationService: WorkspaceCardCommands, WorkspaceSubscriptionCardCommands {
    func retryMailCard(_ id: UUID) async throws {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        try await local.retryMailCard(id)
    }
    func respondToCard(_ id: UUID, version: Int, response: WorkspaceCardResponse) async throws {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        try await local.respondToCard(id, version: version, response: response)
    }
    func saveCardSecret(_ id: UUID, version: Int, secret: String) async throws {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        try await local.saveCardSecret(id, version: version, secret: secret)
    }
}
