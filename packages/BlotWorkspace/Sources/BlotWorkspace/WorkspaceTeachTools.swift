import BlotDomain
import Foundation

/// Only reviewed recordings are executable; an agent cannot submit arbitrary accessibility selectors.
public struct WorkspaceTeachTools: WorkspaceToolExecuting {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceFileService
    private let executor: any NativeExecuting
    private let confirm: @Sendable (String, String) async throws -> Bool
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceFileService, executor: any NativeExecuting,
                confirm: @escaping @Sendable (String, String) async throws -> Bool) {
        self.repository = repository; self.identity = identity; self.files = files; self.executor = executor; self.confirm = confirm
    }
    public var definitions: [ChatToolDefinition] {
        [.init(name: "desktop_replay", description: "Replay a user-recorded, reviewed Teach a task on this physical Mac. recording_id is the saved recording artifact UUID from the skill. Always requires owner approval. Only supported accessibility controls are replayed; ambiguous or changed targets stop execution. No secret fields or raw key events. Report partial completion if a step fails; never automatically retry.",
            parameters: .object(["type": .string("object"), "properties": .object(["recording_id": .object(["type": .string("string")])]), "required": .array([.string("recording_id")]), "additionalProperties": .bool(false)]))]
    }
    private func authorize(_ context: WorkspaceToolContext) async throws {
        guard context.allowedToolIDs.contains("desktop_replay"), let agentID = context.agentID,
              let agent = try await repository.record(BlotV3.AgentProfile.self, id: agentID, workspaceID: identity.workspaceID), agent.accessMode != .observe,
              let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
              WorkspaceToolRestrictions(userRequest: source.content).allows(operation: "update"),
              WorkspaceToolRestrictions(userRequest: source.content).allows(operation: "send"),
              try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: await repository.projection(identity: identity))?.toolIds.contains("desktop_replay") == true else { throw WorkspaceStorageError.permissionDenied }
        if let id = context.taskID {
            guard let task = try await repository.record(BlotV3.Task.self, id: id, workspaceID: identity.workspaceID),
                  task.execution.executorDeviceId == identity.deviceID, !WorkspaceTaskService.terminal(task.state), task.state != .paused else { throw WorkspaceStorageError.permissionDenied }
        }
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        #if os(macOS)
        do { try await authorize(context); return definitions } catch is CancellationError { throw CancellationError() } catch { return [] }
        #else
        return []
        #endif
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        guard call.name == "desktop_replay", let raw = call.arguments.mcpFields["recording_id"]?.mcpString, let id = UUID(uuidString: raw) else { throw WorkspaceToolError.invalidArguments }
        try await authorize(context)
        let data = try await files.data(for: id)
        guard data.count <= 120_000 else { throw WorkspaceStorageError.invalidParameters }
        let recording = try JSONDecoder().decode(WorkspaceTaughtTask.self, from: data); try recording.validate()
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        let actionID = WorkspaceToolCallIdentity.actionID(workspaceID: identity.workspaceID, sourceID: context.sourceMessageID, callID: call.id)
        if let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) {
            guard action.toolId == call.name, action.parameters == String(decoding: try WorkspaceCoding.encode(call.arguments), as: UTF8.self) else { throw NativeExecutionError.changed }
            if let invocation = try await repository.projection(identity: identity).invocations.first(where: { $0.preparedActionId == actionID }),
               [.succeeded, .failed].contains(invocation.state), let result = invocation.result { return try JSONDecoder().decode(ChatJSON.self, from: Data(result.utf8)) }
            throw NativeExecutionError.unknown
        }
        guard let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID), let agentID = context.agentID else { throw WorkspaceStorageError.permissionDenied }
        let taskID: UUID
        if let task = context.taskID { taskID = task }
        else { taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: source.conversationId, agentID: agentID, goal: "Teach: " + recording.application, executorDeviceID: identity.deviceID, runnable: false) }
        let details = recording.application + "\n" + recording.steps.enumerated().map { index, step in
            "\(index + 1). \(step.action.rawValue) · \(step.target.title.isEmpty ? step.target.identifier : step.target.title)" + (step.value.map { " → " + $0 } ?? "")
        }.joined(separator: "\n")
        _ = try await permission.prepare(commandID: actionID, taskID: taskID, draft: .init(toolID: call.name, resource: "application:" + recording.bundleID,
            parametersJSON: String(decoding: WorkspaceCoding.encode(call.arguments), as: UTF8.self), consequences: details), expiresAt: Date().addingTimeInterval(600))
        let action = try requireAction(await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID))
        do {
            let allowed: Bool
            if context.inlineCards { allowed = try await WorkspaceConversationCardService(repository: repository, identity: identity).review(action: action, context: context,
                content: .command(.init(title: "Teach: " + recording.application, details: details, command: "desktop_replay"))).action == "allow" }
            else { allowed = try await confirm("Teach: " + recording.application, details) }
            guard allowed else { throw WorkspaceStorageError.permissionDenied }
            try await authorize(context)
            _ = try await permission.approve(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version, digest: action.digest)
        } catch {
            try? await permission.deny(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version)
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }; throw error
        }
        let invocation = try await permission.begin(actionID: actionID, digest: action.digest)
        guard invocation.applied else { throw NativeExecutionError.unknown }
        var completed = 0
        do {
            _ = try await executor.request(Self.request(.teachReplay, identity: identity, parameters: ["recording": String(decoding: data, as: UTF8.self), "index": "-1"]))
            try await _Concurrency.Task.sleep(for: .milliseconds(600))
            for index in recording.steps.indices {
                try _Concurrency.Task.checkCancellation(); try await authorize(context)
                _ = try await executor.request(Self.request(.teachReplay, identity: identity, parameters: ["recording": String(decoding: data, as: UTF8.self), "index": String(index)]))
                completed += 1
                try await _Concurrency.Task.sleep(for: .milliseconds(450))
            }
            let result = ChatJSON.object(["state": .string("completed"), "steps_completed": .number(Double(completed))])
            try await permission.finish(commandID: UUID(), invocationID: invocation.resultID, state: .succeeded, result: String(decoding: WorkspaceCoding.encode(result), as: UTF8.self))
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
            return result
        } catch {
            let result = ChatJSON.object(["state": .string("stopped"), "steps_completed": .number(Double(completed)), "reason": .string("Target changed, unavailable, or task stopped. Inspect the application before running again.")])
            try? await permission.finish(commandID: UUID(), invocationID: invocation.resultID, state: error as? NativeExecutionError == .changed ? .failed : .unknown, result: String(decoding: WorkspaceCoding.encode(result), as: UTF8.self))
            if error is CancellationError { throw error }; return result
        }
    }
    public static func request(_ operation: NativeRequest.Operation, identity: WorkspaceIdentity, parameters: [String: String] = [:]) -> NativeRequest {
        .init(operation, command: .init(projectID: identity.workspaceID, root: "/", executable: "/usr/bin/true"), parameters: parameters)
    }
}

private func requireAction(_ value: BlotV3.PreparedAction?) throws -> BlotV3.PreparedAction {
    guard let value else { throw WorkspaceStorageError.missingRecord }; return value
}
