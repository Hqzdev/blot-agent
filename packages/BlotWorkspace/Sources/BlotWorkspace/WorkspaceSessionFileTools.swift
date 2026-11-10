import BlotDomain
import Foundation

public struct WorkspaceSessionFileTools: WorkspaceToolExecuting {
    private let service: WorkspaceSessionFileService?
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(service: WorkspaceSessionFileService?, repository: WorkspaceRepository, identity: WorkspaceIdentity) {
        self.service = service; self.repository = repository; self.identity = identity
    }
    public var definitions: [ChatToolDefinition] { WorkspaceSessionFileCatalog.definitions }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        guard let service else { return [] }; return try await service.availableDefinitions(context: context)
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        do { return try await perform(call, context: context) }
        catch is CancellationError { throw CancellationError() }
        catch { return .object(["state": .string((error as? NativeExecutionError) == .unknown ? "unknown" : "failed"),
                               "error": .string((error as? NativeExecutionError)?.localizedDescription ?? "Операция с файлами не выполнена.")]) }
    }
    private func perform(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        guard let service else { throw NativeExecutionError.unavailable }
        let conversation = try await service.authorize(call.name, context: context)
        let actionID = WorkspaceLogicalID.make(kind: "SessionFileAction", workspaceID: identity.workspaceID, parts: [context.sourceMessageID.uuidString, call.id])
        if !WorkspaceSessionFileCatalog.writes(call.name) { return try await service.perform(call, context: context, actionID: actionID) }
        let parameters = String(decoding: try WorkspaceCoding.encode(call.arguments), as: UTF8.self)
        guard parameters.utf8.count <= 48 * 1024 else { throw NativeExecutionError.invalidRequest }
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        if let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) {
            guard action.toolId == call.name,
                  (try? WorkspaceCoding.decode(ChatJSON.self, from: Data(action.parameters.utf8))) == call.arguments else { throw NativeExecutionError.accessDenied }
            let projection = try await repository.projection(identity: identity)
            if let invocation = projection.invocations.first(where: { $0.preparedActionId == actionID }), invocation.state == .succeeded, let result = invocation.result {
                return try WorkspaceCoding.decode(ChatJSON.self, from: Data(result.utf8))
            }
            if [.failed, .denied, .expired].contains(action.state) || projection.invocations.contains(where: { $0.preparedActionId == actionID && $0.state == .failed }) { throw NativeExecutionError.accessDenied }
            throw NativeExecutionError.unknown
        }
        let taskID: UUID
        if let id = context.taskID { taskID = id }
        else { taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: conversation,
            agentID: context.agentID!, goal: "Файлы сессии · " + call.name, executorDeviceID: identity.deviceID, runnable: false) }
        _ = try await permission.prepare(commandID: actionID, taskID: taskID, draft: .init(toolID: call.name,
            resource: "session-files:" + conversation.uuidString, parametersJSON: parameters,
            consequences: call.name == "workspace_request_directory" ? "Владелец выбирает внешнюю папку в системном диалоге. Отмена не выдаёт доступ." : "Запись только в рабочую папку сессии или ранее выбранную владельцем папку."), expiresAt: Date().addingTimeInterval(600))
        guard let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) else { throw NativeExecutionError.unknown }
        _ = try await permission.approve(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version, digest: action.digest)
        let outcome = try await permission.begin(actionID: actionID, digest: action.digest)
        guard outcome.applied else { throw NativeExecutionError.unknown }
        do {
            let result = try await service.perform(call, context: context, actionID: actionID)
            try await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: .succeeded, result: String(decoding: try WorkspaceCoding.encode(result), as: UTF8.self))
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
            return result
        } catch {
            let known = [NativeExecutionError.accessDenied, .invalidRequest, .changed, .busy].contains(error as? NativeExecutionError ?? .unknown)
            try? await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: known ? .failed : .unknown)
            if context.taskID == nil && known { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }
            if error is CancellationError { throw error }; throw known ? error : NativeExecutionError.unknown
        }
    }
}
