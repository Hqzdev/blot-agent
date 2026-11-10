import BlotDomain
import Foundation
import OSLog

/// One durable loop for chat and tasks. Tools are called only from complete, validated model turns.
public struct WorkspaceModelRuntime: Sendable {
    private let logger = Logger(subsystem: "dev.blot.model", category: "Runtime")
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let pool: WorkspaceExecutorPool
    private let tools: WorkspaceToolRegistry
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, pool: WorkspaceExecutorPool, tools: WorkspaceToolRegistry) {
        self.repository = repository; self.identity = identity; self.pool = pool; self.tools = tools
    }
    public func generate(source: BlotV3.Message, responseID: UUID, request: ChatModelRequest, model: any ChatModel, modelID: String,
                         configuration: BlotV3.AgentConfigurationRevision?, taskID: UUID? = nil, skillRevisionID: UUID? = nil,
                         budgetTokenLimit: Int, toolsEnabled: Bool = true, executionToolIDs: Set<String>? = nil,
                         checkpoint: WorkspaceTaskCheckpoint? = nil, previousOperations: WorkspaceGroupOperationHistory? = nil,
                         validateExecution: (@Sendable () async throws -> Void)? = nil, emit: @escaping @Sendable (BlotV3.Message) -> Void) async throws {
        let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
        let steps = WorkspaceModelStepService(repository: repository, identity: identity)
        let budgets = WorkspaceBudgetService(repository: repository, identity: identity)
        let initialProjection = try await repository.projection(identity: identity)
        let skillTools = toolsEnabled && taskID == nil ? WorkspaceSkillAccess.internalToolIDs(agentID: configuration?.agentId, projection: initialProjection) : []
        let assigned = Set(toolsEnabled ? configuration?.toolIds ?? [] : []).union(skillTools)
        let allowed = executionToolIDs.map { assigned.intersection($0) } ?? assigned
        let initialContext = WorkspaceToolContext(sourceMessageID: source.metadata.id, taskID: taskID, allowedToolIDs: allowed, agentID: configuration?.agentId)
        let definitions = try await tools.availableDefinitions(context: initialContext)
        var context = request.messages
        if let checkpoint, !checkpoint.messages.isEmpty { context = checkpoint.messages }
        else {
            context.insert(.init(role: "system", content: WorkspaceAgentInstructions.behavior + "\n" + WorkspaceAgentInstructions.clock()), at: 0)
            if !definitions.isEmpty {
                context.insert(.init(role: "system", content:
                    "For quick tool actions, call the tool directly and report the result once. " +
                    "Give a short progress update only for longer work or required user interaction; do not repeat acknowledgements on each tool turn. " +
                    "Never claim an action succeeded before its tool result confirms success. " +
                    "For a requested saved skill, discover assigned skills with skill_list, then use skill_run with its required values. Never invent missing values. A queued skill is not completed; its task will post the result separately. Do not launch unrelated skills. " +
                    "When reporting an app tool result, mention its user-facing @App name from the tool description once in your sentence. " +
                    "Do not print internal function names or Args blocks as mentions."), at: 0)
            }
            // Keep the current reply policy after legacy role instructions and examples.
            context.insert(.init(role: "system", content: WorkspaceAgentInstructions.replyStyle), at: max(0, context.count - 1))
        }
        var activeResponseID = responseID
        var pendingText = ""
        var charged = 0
        do {
            for offset in 0..<24 {
                let index = (checkpoint?.nextStepIndex ?? 0) + offset
                pendingText = ""
                try await validateExecution?()
                try await checkExecution(taskID: taskID, delegated: validateExecution != nil)
                let liveConfiguration = try await repository.projection(identity: identity)
                let currentConfiguration = try WorkspaceAgentConfigurationResolver().resolve(agentID: configuration?.agentId, projection: liveConfiguration)
                let liveSkillTools = toolsEnabled && taskID == nil ? WorkspaceSkillAccess.internalToolIDs(agentID: configuration?.agentId, projection: liveConfiguration) : []
                let currentAssigned = Set(toolsEnabled ? currentConfiguration?.toolIds ?? [] : []).union(liveSkillTools)
                let currentAllowed = taskID == nil ? (executionToolIDs.map { currentAssigned.intersection($0) } ?? currentAssigned) : currentAssigned.intersection(allowed)
                let toolContext = WorkspaceToolContext(sourceMessageID: source.metadata.id, taskID: taskID, allowedToolIDs: currentAllowed, agentID: configuration?.agentId)
                let currentDefinitions = try await tools.availableDefinitions(context: toolContext)
                let turn = ChatModelRequest(messages: context, tools: currentDefinitions, maximumOutputTokens: request.maximumOutputTokens)
                // A conservative local reservation bounds unknown provider cost; estimates are never shown as billed usage.
                let reservation = try JSONEncoder().encode(turn).count + turn.maximumOutputTokens
                logger.debug("Model turn response=\(responseID, privacy: .public) index=\(index) reservedBytes=\(reservation) tools=\(currentDefinitions.count)")
                guard reservation > 0, charged <= budgetTokenLimit, reservation <= budgetTokenLimit - charged else {
                    throw WorkspaceStorageError.permissionDenied
                }
                let stepID = WorkspaceLogicalID.make(kind: "ModelStep", workspaceID: identity.workspaceID, parts: [responseID.uuidString, String(index)])
                let budgetRequestID = WorkspaceLogicalID.make(kind: "ModelBudget", workspaceID: identity.workspaceID, parts: [stepID.uuidString])
                if let taskID { _ = try await budgets.reserve(requestID: budgetRequestID, taskID: taskID, tokens: reservation, limit: budgetTokenLimit) }
                try await steps.begin(id: stepID, source: source, responseID: activeResponseID, request: turn, modelID: modelID,
                    configurationID: configuration?.metadata.id, taskID: taskID, skillRevisionID: skillRevisionID,
                    stepIndex: index, budgetTokenLimit: budgetTokenLimit)
                var usage: ChatModelUsage?
                var calls: [ChatToolCall] = []
                var reason: ChatModelFinish?
                do {
                    try await pool.acquire()
                    do {
                        try await validateExecution?()
                        try await checkExecution(taskID: taskID, delegated: validateExecution != nil)
                        for try await event in model.stream(request: turn) {
                            try await checkExecution(taskID: taskID, delegated: validateExecution != nil)
                            switch event {
                            case .text(let delta):
                                guard reason == nil else { throw ChatModelError.invalidStream }
                                pendingText += delta
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
                    try await validateExecution?()
                    if taskID != nil { try await budgets.settle(commandID: UUID(), requestID: budgetRequestID, actualTokens: usage?.totalTokens) }
                    charged += min(usage?.totalTokens ?? reservation, budgetTokenLimit - charged)
                    guard let reason, reason != .length else { throw ChatModelError.interrupted }
                    if reason == .stop {
                        guard calls.isEmpty else { throw ChatModelError.invalidStream }
                        try await steps.finish(id: stepID, state: .completed, usage: usage)
                        emit(try await recorder.finish(activeResponseID, delivery: .completed, content: pendingText))
                        return
                    }
                    guard !calls.isEmpty, calls.count <= 64 else { throw ChatModelError.invalidStream }
                    // The entire set of calls is durable before the first tool executes.
                    try await steps.finish(id: stepID, state: .waiting_tools, calls: calls, usage: usage)
                    context.append(.init(role: "assistant", content: pendingText, toolCalls: calls))
                    if !pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Each finished model turn gets its own bubble, before any tool starts.
                        emit(try await recorder.finish(activeResponseID, delivery: .completed, content: pendingText))
                        pendingText = ""
                        let next = try await recorder.begin(id: UUID(), replyingTo: source, agentID: configuration?.agentId)
                        activeResponseID = next.metadata.id
                        emit(next)
                    }
                    var results: [String: ChatJSON] = [:]
                    for call in calls {
                        try await validateExecution?()
                        try await checkExecution(taskID: taskID, delegated: validateExecution != nil)
                        guard charged < budgetTokenLimit else { throw WorkspaceStorageError.permissionDenied }
                        let result: ChatJSON
                        if let recorded = try checkpoint?.recordedResult(for: call) ?? previousOperations?.result(for: call) { result = recorded }
                        else { result = try await tools.execute(call, context: toolContext) }
                        if call.name == "document_create", case .object(let fields) = result,
                           case .string(let rawID) = fields["artifact_id"], let id = UUID(uuidString: rawID) {
                            emit(try await recorder.attach(id, to: activeResponseID))
                        }
                        logger.debug("Tool returned response=\(responseID, privacy: .public) name=\(call.name, privacy: .public)")
                        results[call.id] = result
                        // Persist each result before executing another call or returning to the model.
                        try await steps.finish(id: stepID, state: .waiting_tools, calls: calls, results: results, usage: usage)
                        context.append(.init(role: "tool", content: String(decoding: try JSONEncoder().encode(result), as: UTF8.self),
                            toolCallID: call.id, name: call.name))
                    }
                    try await steps.finish(id: stepID, state: .completed, calls: calls, results: results, usage: usage)
                } catch {
                    if taskID != nil { try? await budgets.settle(commandID: UUID(), requestID: budgetRequestID, actualTokens: usage?.totalTokens) }
                    try? await steps.finish(id: stepID, state: _Concurrency.Task.isCancelled ? .canceled : .interrupted, calls: calls, usage: usage)
                    throw error
                }
            }
            throw WorkspaceStorageError.permissionDenied
        } catch {
            let state: BlotV3.DeliveryState = _Concurrency.Task.isCancelled ? .canceled : .interrupted
            if let saved = try? await recorder.finish(activeResponseID, delivery: state, content: pendingText) { emit(saved) }
            throw error
        }
    }
    private func checkExecution(taskID: UUID?, delegated: Bool) async throws {
        try _Concurrency.Task.checkCancellation()
        guard let taskID else { return }
        let projection = try await repository.taskExecutionProjection(identity: identity)
        guard var task = projection.tasks.first(where: { $0.metadata.id == taskID }),
              task.execution.executorDeviceId == identity.deviceID, (task.execution.originDeviceId == identity.deviceID && task.executionMode == .local_owned || delegated && task.executionMode == .delegated && task.execution.originDeviceId != identity.deviceID && task.authorizationJSON != nil) else { throw WorkspaceStorageError.permissionDenied }
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
