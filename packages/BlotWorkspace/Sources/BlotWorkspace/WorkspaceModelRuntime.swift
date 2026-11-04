import BlotDomain
import Foundation

/// One durable loop for chat and tasks. Tools are called only from complete, validated model turns.
public struct WorkspaceModelRuntime: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let pool: WorkspaceExecutorPool
    private let tools: WorkspaceToolRegistry
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, pool: WorkspaceExecutorPool, tools: WorkspaceToolRegistry) {
        self.repository = repository; self.identity = identity; self.pool = pool; self.tools = tools
    }
    public func generate(source: BlotV3.Message, responseID: UUID, request: ChatModelRequest, model: any ChatModel, modelID: String,
                         configuration: BlotV3.AgentConfigurationRevision?, taskID: UUID? = nil, skillRevisionID: UUID? = nil,
                         budgetTokenLimit: Int, emit: @escaping @Sendable (BlotV3.Message) -> Void) async throws {
        let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
        let steps = WorkspaceModelStepService(repository: repository, identity: identity)
        let budgets = WorkspaceBudgetService(repository: repository, identity: identity)
        let allowed = Set(configuration?.toolIds ?? [])
        let definitions = tools.definitions(allowed: allowed)
        var context = request.messages
        var charged = 0
        for index in 0..<24 {
            try await checkExecution(taskID: taskID)
            let turn = ChatModelRequest(messages: context, tools: definitions, maximumOutputTokens: request.maximumOutputTokens)
            // A conservative local reservation bounds unknown provider cost; estimates are never shown as billed usage.
            let reservation = try JSONEncoder().encode(turn).count + turn.maximumOutputTokens
            guard reservation > 0, charged <= budgetTokenLimit, reservation <= budgetTokenLimit - charged else {
                throw WorkspaceStorageError.permissionDenied
            }
            let stepID = WorkspaceLogicalID.make(kind: "ModelStep", workspaceID: identity.workspaceID, parts: [responseID.uuidString, String(index)])
            if let taskID { _ = try await budgets.reserve(requestID: stepID, taskID: taskID, tokens: reservation, limit: budgetTokenLimit) }
            try await steps.begin(id: stepID, source: source, responseID: responseID, request: turn, modelID: modelID,
                configurationID: configuration?.metadata.id, taskID: taskID, skillRevisionID: skillRevisionID,
                stepIndex: index, budgetTokenLimit: budgetTokenLimit)
            var usage: ChatModelUsage?
            var calls: [ChatToolCall] = []
            var text = ""
            var reason: ChatModelFinish?
            do {
                try await pool.acquire()
                do {
                    try await checkExecution(taskID: taskID)
                    for try await event in model.stream(request: turn) {
                        try await checkExecution(taskID: taskID)
                        switch event {
                        case .text(let delta):
                            guard reason == nil else { throw ChatModelError.invalidStream }
                            text += delta
                            emit(try await recorder.append(delta, to: responseID))
                        case .toolCall(let call):
                            guard reason == nil, !calls.contains(where: { $0.id == call.id }) else { throw ChatModelError.invalidStream }
                            calls.append(call)
                        case .usage(let value):
                            guard usage == nil || usage == value else { throw ChatModelError.invalidStream }
                            usage = value
                        case .finished(let value):
                            guard reason == nil else { throw ChatModelError.invalidStream }
                            reason = value
                        case .failure(let error): throw error
                        }
                    }
                    await pool.release()
                } catch { await pool.release(); throw error }
                if taskID != nil { try await budgets.settle(commandID: UUID(), requestID: stepID, actualTokens: usage?.totalTokens) }
                charged += min(usage?.totalTokens ?? reservation, budgetTokenLimit - charged)
                guard let reason, reason != .length else { throw ChatModelError.interrupted }
                if reason == .stop {
                    guard calls.isEmpty else { throw ChatModelError.invalidStream }
                    try await steps.finish(id: stepID, state: .completed, usage: usage)
                    emit(try await recorder.finish(responseID, delivery: .completed))
                    return
                }
                guard !calls.isEmpty, calls.count <= 64 else { throw ChatModelError.invalidStream }
                // The entire set of calls is durable before the first tool executes.
                try await steps.finish(id: stepID, state: .waiting_tools, calls: calls, usage: usage)
                context.append(.init(role: "assistant", content: text, toolCalls: calls))
                var results: [String: ChatJSON] = [:]
                for call in calls {
                    try await checkExecution(taskID: taskID)
                    guard charged < budgetTokenLimit else { throw WorkspaceStorageError.permissionDenied }
                    let result = try await tools.execute(call, context: .init(sourceMessageID: source.metadata.id, taskID: taskID, allowedToolIDs: allowed))
                    results[call.id] = result
                    // Persist each result before executing another call or returning to the model.
                    try await steps.finish(id: stepID, state: .waiting_tools, calls: calls, results: results, usage: usage)
                    context.append(.init(role: "tool", content: String(decoding: try JSONEncoder().encode(result), as: UTF8.self),
                        toolCallID: call.id, name: call.name))
                }
                try await steps.finish(id: stepID, state: .completed, calls: calls, results: results, usage: usage)
            } catch {
                if taskID != nil { try? await budgets.settle(commandID: UUID(), requestID: stepID, actualTokens: usage?.totalTokens) }
                try? await steps.finish(id: stepID, state: _Concurrency.Task.isCancelled ? .canceled : .interrupted, calls: calls, usage: usage)
                throw error
            }
        }
        throw WorkspaceStorageError.permissionDenied
    }
    private func checkExecution(taskID: UUID?) async throws {
        try _Concurrency.Task.checkCancellation()
        guard let taskID else { return }
        let projection = try await repository.projection(identity: identity)
        guard var task = projection.tasks.first(where: { $0.metadata.id == taskID }),
              task.execution.executorDeviceId == identity.deviceID, task.execution.originDeviceId == identity.deviceID,
              task.executionMode == .local_owned else { throw WorkspaceStorageError.permissionDenied }
        var visited: Set<UUID> = []
        while true {
            guard visited.insert(task.metadata.id).inserted, visited.count <= 3,
                  !WorkspaceTaskService.terminal(task.state), task.state != .paused,
                  !projection.invocations.contains(where: { $0.execution.taskId == task.metadata.id && $0.state == .unknown }) else {
                throw WorkspaceStorageError.permissionDenied
            }
            guard let parent = task.parentTaskId else { return }
            guard let ancestor = projection.tasks.first(where: { $0.metadata.id == parent }) else { throw WorkspaceStorageError.missingRecord }
            task = ancestor
        }
    }
}
