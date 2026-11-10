import BlotDomain
import Foundation

/// Freezes model input and accounts provider usage once per request, including unknown usage after an interruption.
public struct WorkspaceModelStepService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }
    public func begin(id: UUID, source: BlotV3.Message, responseID: UUID, request: ChatModelRequest, modelID: String,
                      configurationID: UUID?, taskID: UUID? = nil, skillRevisionID: UUID? = nil,
                      stepIndex: Int = 0, budgetTokenLimit: Int, now: Date = Date()) async throws {
        let requestJSON = String(decoding: try WorkspaceCoding.encode(request), as: UTF8.self)
        struct Input: Encodable { let sourceID: UUID; let responseID: UUID; let requestJSON: String; let modelID: String; let configurationID: UUID?; let taskID: UUID?; let skillRevisionID: UUID?; let stepIndex: Int; let budget: Int }
        let command = try WorkspaceCommand(type: "model.begin", workspaceID: identity.workspaceID,
            payload: Input(sourceID: source.metadata.id, responseID: responseID, requestJSON: requestJSON, modelID: modelID,
                configurationID: configurationID, taskID: taskID, skillRevisionID: skillRevisionID, stepIndex: stepIndex, budget: budgetTokenLimit)).data()
        _ = try await repository.execute(commandID: id, command: command, identity: identity) { tx in
            let saved = try tx.require(BlotV3.Message.self, id: source.metadata.id)
            let response = try tx.require(BlotV3.Message.self, id: responseID)
            guard saved.role == .user, response.conversationId == saved.conversationId, response.executorDeviceId == tx.identity.deviceID,
                  budgetTokenLimit >= request.maximumOutputTokens, request.maximumOutputTokens > 0 else { throw WorkspaceStorageError.permissionDenied }
            if let configurationID { _ = try tx.require(BlotV3.AgentConfigurationRevision.self, id: configurationID) }
            if let skillRevisionID { _ = try tx.require(BlotV3.SkillRevision.self, id: skillRevisionID) }
            var mode: BlotV3.ExecutionMode = .local_owned
            if let taskID {
                let task = try tx.require(BlotV3.Task.self, id: taskID)
                guard task.execution.executorDeviceId == tx.identity.deviceID, !WorkspaceTaskService.terminal(task.state),
                      let executionMode = task.executionMode else { throw WorkspaceStorageError.permissionDenied }
                mode = executionMode
                // Delegated work must acquire and fence a server lease before a runtime can run it.
                guard (mode == .local_owned && task.execution.originDeviceId == tx.identity.deviceID) || (mode == .delegated && task.authorizationJSON != nil) else { throw WorkspaceStorageError.permissionDenied }
            }
            let step = try BlotV3.ModelStep(metadata: tx.metadata(id: id, now: now), conversationId: saved.conversationId,
                sourceMessageId: saved.metadata.id, responseMessageId: responseID, taskId: taskID,
                executorDeviceId: tx.identity.deviceID, originDeviceId: tx.identity.deviceID, executionMode: mode,
                stepIndex: stepIndex, modelId: modelID, configurationId: configurationID, skillRevisionId: skillRevisionID,
                budgetTokenLimit: budgetTokenLimit, requestJSON: requestJSON, toolCallsJSON: nil, toolResultsJSON: nil,
                inputTokens: nil, outputTokens: nil, state: .running)
            try tx.put(step, expectedVersion: 0)
            return id
        }
    }
    public func finish(id: UUID, state: BlotV3.ModelStepState, calls: [ChatToolCall] = [], results: [String: ChatJSON] = [:],
                       usage: ChatModelUsage?, now: Date = Date()) async throws {
        let callsJSON = calls.isEmpty ? nil : String(decoding: try WorkspaceCoding.encode(calls), as: UTF8.self)
        let resultsJSON = results.isEmpty ? nil : String(decoding: try WorkspaceCoding.encode(results), as: UTF8.self)
        struct Input: Encodable { let id: UUID; let state: BlotV3.ModelStepState; let calls: String?; let results: String?; let usage: ChatModelUsage? }
        let command = try WorkspaceCommand(type: "model.finish", workspaceID: identity.workspaceID,
            payload: Input(id: id, state: state, calls: callsJSON, results: resultsJSON, usage: usage)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let old = try tx.require(BlotV3.ModelStep.self, id: id)
            guard old.executorDeviceId == tx.identity.deviceID, old.originDeviceId == tx.identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
            if old.state != .running && old.state != .waiting_tools {
                guard old.state == state, old.inputTokens == usage?.inputTokens, old.outputTokens == usage?.outputTokens,
                      old.toolCallsJSON == callsJSON, old.toolResultsJSON == resultsJSON else { throw WorkspaceStorageError.commandConflict }
                return id
            }
            guard state != .running, state != .prepared,
                  old.inputTokens == nil || old.inputTokens == usage?.inputTokens,
                  old.outputTokens == nil || old.outputTokens == usage?.outputTokens else { throw WorkspaceStorageError.invalidParameters }
            let updated = try BlotV3.ModelStep(metadata: tx.metadata(id: id, now: now, replacing: old.metadata),
                conversationId: old.conversationId, sourceMessageId: old.sourceMessageId, responseMessageId: old.responseMessageId,
                taskId: old.taskId, executorDeviceId: old.executorDeviceId, originDeviceId: old.originDeviceId, executionMode: old.executionMode,
                stepIndex: old.stepIndex, modelId: old.modelId, configurationId: old.configurationId, skillRevisionId: old.skillRevisionId,
                budgetTokenLimit: old.budgetTokenLimit, requestJSON: old.requestJSON, toolCallsJSON: callsJSON, toolResultsJSON: resultsJSON ?? old.toolResultsJSON,
                inputTokens: usage?.inputTokens, outputTokens: usage?.outputTokens, state: state)
            try tx.put(updated, expectedVersion: old.metadata.version)
            return id
        }
    }
    public func recoverInterrupted() async throws {
        let steps = try await repository.records(BlotV3.ModelStep.self, workspaceID: identity.workspaceID)
        for step in steps where step.executorDeviceId == identity.deviceID && step.originDeviceId == identity.deviceID && step.state == .running {
            try await finish(id: step.metadata.id, state: .interrupted, usage: nil)
        }
    }
}
