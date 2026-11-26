import BlotDomain
import Foundation

/// Durable at-most-once boundary for remote writes. Transport failures after claiming remain unknown.
struct WorkspaceExternalReview: Sendable {
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let confirm: @Sendable (String, String) async throws -> Bool
    func run(call: ChatToolCall, context: WorkspaceToolContext, resource: String, content: WorkspaceCardContent,
             authorize: @Sendable () async throws -> Void,
             perform: @Sendable (WorkspaceCardResponse?) async throws -> ChatJSON) async throws -> ChatJSON {
        try await authorize()
        let permissions = WorkspacePermissionService(repository: repository, identity: identity)
        let id = WorkspaceToolCallIdentity.actionID(workspaceID: identity.workspaceID, sourceID: context.sourceMessageID, callID: call.id)
        let arguments = String(decoding: try WorkspaceCoding.encode(call.arguments), as: UTF8.self)
        if let old = try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID) {
            guard old.toolId == call.name, old.resource == resource,
                  try JSONDecoder().decode(ChatJSON.self, from: Data(old.parameters.utf8)) == call.arguments else { throw WorkspaceStorageError.commandConflict }
            if let invocation = try await repository.projection(identity: identity).invocations.first(where: { $0.preparedActionId == id }),
               [.succeeded, .failed].contains(invocation.state), let result = invocation.result { return try JSONDecoder().decode(ChatJSON.self, from: Data(result.utf8)) }
            throw NativeExecutionError.unknown
        }
        guard let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID), let agentID = context.agentID else { throw WorkspaceStorageError.permissionDenied }
        let taskID: UUID
        if let task = context.taskID { taskID = task }
        else { taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: source.conversationId,
            agentID: agentID, goal: call.name, executorDeviceID: identity.deviceID, runnable: false) }
        _ = try await permissions.prepare(commandID: id, taskID: taskID, draft: .init(toolID: call.name, resource: resource,
            parametersJSON: arguments, consequences: String(decoding: try JSONEncoder().encode(content), as: UTF8.self)), expiresAt: Date().addingTimeInterval(600))
        guard let action = try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID) else { throw WorkspaceStorageError.missingRecord }
        var response: WorkspaceCardResponse?
        do {
            let mandatory = ["gmail_send"].contains(call.name)
            let review = try await WorkspaceRuleService(repository: repository, identity: identity).requiresReview(toolID: call.name,
                resource: resource, agentID: context.agentID, default: true, mandatory: mandatory)
            if review {
                if context.inlineCards {
                    response = try await WorkspaceConversationCardService(repository: repository, identity: identity).review(action: action, context: context, content: content)
                    guard ["send", "allow"].contains(response?.action ?? "") else { throw WorkspaceStorageError.permissionDenied }
                } else { guard try await confirm(call.name, arguments) else { throw WorkspaceStorageError.permissionDenied } }
            }
            try await authorize()
            _ = try await permissions.approve(commandID: UUID(), actionID: id, expectedVersion: action.metadata.version, digest: action.digest)
        } catch {
            try? await permissions.deny(commandID: UUID(), actionID: id, expectedVersion: action.metadata.version)
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }; throw error
        }
        let invocation = try await permissions.begin(actionID: id, digest: action.digest)
        guard invocation.applied else { throw NativeExecutionError.unknown }
        do {
            try await authorize(); let result = try await perform(response)
            try await permissions.finish(commandID: UUID(), invocationID: invocation.resultID, state: .succeeded,
                result: String(decoding: WorkspaceCoding.encode(result), as: UTF8.self))
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
            return result
        } catch {
            let known = error as? GoogleOAuthError == .accessDenied || error as? GoogleOAuthError == .authorizationExpired || error as? WorkspaceStorageError == .invalidParameters
            try? await permissions.finish(commandID: UUID(), invocationID: invocation.resultID, state: known ? .failed : .unknown)
            if error is CancellationError { throw error }; throw error
        }
    }
}
