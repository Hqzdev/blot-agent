import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor TaskModel: ChatModel {
    private var requests: [ChatModelRequest] = []
    private let turns: [[ChatModelEvent]]
    private let suspendAt: Int?
    init(_ turns: [[ChatModelEvent]], suspendAt: Int? = nil) { self.turns = turns; self.suspendAt = suspendAt }
    var count: Int { requests.count }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                do {
                    let (events, suspended) = await next(request)
                    if suspended { try await _Concurrency.Task.sleep(for: .seconds(30)) }
                    for event in events { try _Concurrency.Task.checkCancellation(); continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
    private func next(_ request: ChatModelRequest) -> ([ChatModelEvent], Bool) {
        let index = requests.count; requests.append(request)
        return (index < turns.count ? turns[index] : [.text("Done"), .finished(.stop)], suspendAt == index)
    }
}

private actor TaskWriteTool: WorkspaceToolExecuting {
    nonisolated let definitions = [ChatToolDefinition(name: "write", description: "Create one item", parameters:
        .object(["type": .string("object"), "properties": .object([:])]))]
    private(set) var count = 0
    private(set) var writes = 0
    private let failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        count += 1
        if failFirst && count == 1 { return .object(["state": .string("failed"), "error": .string("Not created")]) }
        writes += 1
        return .object(["id": .string("created-\(count)")])
    }
}

private struct TaskFixture: Sendable {
    let directory: URL
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let conversationID: UUID
    let agentID: UUID
    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("tasks.sqlite"))
        identity = try await repository.localIdentity()
        agentID = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Worker", instructions: "Complete the task", modelID: "gigachat", toolIDs: ["write"]))
        conversationID = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Tasks", agentID: agentID)
    }
    var lifecycle: WorkspaceTaskLifecycle { .init(repository: repository, identity: identity) }
    func create(executor: UUID? = nil, runnable: Bool = true) async throws -> UUID {
        try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: conversationID,
            agentID: agentID, goal: "Create one item", executorDeviceID: executor ?? identity.deviceID, budgetTokenLimit: 100_000, runnable: runnable)
    }
    func execution(tool: TaskWriteTool = TaskWriteTool()) throws -> WorkspaceTaskExecution {
        .init(repository: repository, identity: identity, pool: .init(), tools: try .init(providers: [tool]), maximumOutputTokens: 64)
    }
    func state(_ id: UUID) async throws -> BlotV3.TaskState? { try await repository.record(BlotV3.Task.self, id: id, workspaceID: identity.workspaceID)?.state }
}

private func waitForTask(_ condition: @Sendable () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while try await !condition(), ContinuousClock.now < deadline { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
    #expect(try await condition())
}

@Test func taskClaimIsAtomicAndControlStateSurvivesReload() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let id = try await fixture.create()
    async let first = fixture.lifecycle.claim(id)
    async let second = fixture.lifecycle.claim(id)
    let claims = try await [first, second]
    #expect(claims.filter { $0 }.count == 1)
    let oldVersion = try #require(try await fixture.repository.record(BlotV3.Task.self, id: id, workspaceID: fixture.identity.workspaceID)?.metadata.version)
    try await fixture.lifecycle.pause(commandID: UUID(), taskID: id)
    // A finishing worker must not overwrite the user's pause.
    try await fixture.lifecycle.finish(taskID: id, state: .completed)
    let reopened = try await workspaceTestRepository(url: fixture.directory.appendingPathComponent("tasks.sqlite"))
    let projection = try await reopened.projection(identity: fixture.identity)
    #expect(projection.tasks.first?.state == .paused)
    #expect(projection.sessions.first?.state == .paused)
    #expect(projection.messages.filter { $0.role == .user }.count == 1)
    try await fixture.lifecycle.resume(commandID: UUID(), taskID: id)
    #expect(try await fixture.state(id) == .queued)
    #expect(try await fixture.lifecycle.claim(id))
    try await fixture.lifecycle.finish(taskID: id, state: .completed, expectedVersion: oldVersion)
    #expect(try await fixture.state(id) == .running)
    let remote = try await fixture.create(executor: UUID())
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await fixture.lifecycle.claim(remote) }
}

@Test func taskQueueExecutesLocalWorkOnceAndSkipsBookkeepingAndRemoteTasks() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let first = try await fixture.create(), second = try await fixture.create()
    let remote = try await fixture.create(executor: UUID()), bookkeeping = try await fixture.create(runnable: false)
    let model = TaskModel([]), execution = try fixture.execution()
    let queue = WorkspaceTaskQueue(repository: fixture.repository, identity: fixture.identity, execute: { try await execution.run(taskID: $0, model: model) })
    await queue.start()
    try await waitForTask {
        let a = try await fixture.state(first), b = try await fixture.state(second)
        return a == .completed && b == .completed
    }
    await queue.stop()
    #expect(await model.count == 2)
    let projection = try await fixture.repository.projection(identity: fixture.identity)
    #expect(projection.budgets.count == 2)
    #expect(Set(projection.budgets.map(\.metadata.id)).isDisjoint(with: Set(projection.modelSteps.map(\.metadata.id))))
    #expect(try await fixture.state(remote) == .queued)
    #expect(try await fixture.state(bookkeeping) == .waiting_approval)
    await queue.start(); await queue.stop()
    #expect(await model.count == 2)
}

@Test(arguments: [false, true]) func pausedTaskResumesWithToolResultsWithoutRepeatingTheWrite(_ failFirst: Bool) async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let id = try await fixture.create(), tool = TaskWriteTool(failFirst: failFirst)
    let call = ChatToolCall(id: "original", name: "write", arguments: .object([:]))
    let model = TaskModel([[.toolCall(call), .finished(.toolCalls)]], suspendAt: 1)
    let execution = try fixture.execution(tool: tool)
    let worker = _Concurrency.Task { try await execution.run(taskID: id, model: model) }
    try await waitForTask { await model.count == 2 }
    try await fixture.lifecycle.pause(commandID: UUID(), taskID: id)
    worker.cancel(); _ = await worker.result
    #expect(try await fixture.state(id) == .paused)
    #expect(await tool.count == 1)
    try await fixture.lifecycle.resume(commandID: UUID(), taskID: id)
    // Reuse a completed write, but allow retrying an operation known not to have happened.
    let repeated = ChatToolCall(id: "new-id", name: "write", arguments: .object([:]))
    try await execution.run(taskID: id, model: TaskModel([[.toolCall(repeated), .finished(.toolCalls)], [.text("I created the item."), .finished(.stop)]]))
    #expect(await tool.count == (failFirst ? 2 : 1))
    #expect(await tool.writes == 1)
    #expect(try await fixture.state(id) == .completed)
    let projection = try await fixture.repository.projection(identity: fixture.identity)
    #expect(projection.messages.filter { $0.role == .user }.count == 1)
    #expect(projection.sessions.first?.state == .completed)
}

@Test func taskCancellationCannotBeUndoneByLateWorkerCompletion() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let id = try await fixture.create(), model = TaskModel([], suspendAt: 0)
    let execution = try fixture.execution()
    let worker = _Concurrency.Task { try await execution.run(taskID: id, model: model) }
    try await waitForTask { await model.count == 1 }
    try await WorkspaceTaskService(repository: fixture.repository, identity: fixture.identity).cancel(commandID: UUID(), taskID: id)
    worker.cancel(); _ = await worker.result
    #expect(try await fixture.state(id) == .canceled)
    await #expect(throws: WorkspaceTaskExecutionError.notRunnable) { try await fixture.lifecycle.resume(commandID: UUID(), taskID: id) }
}

@Test func recoveryRequeuesSafeWorkAndBlocksMissingToolOutcomes() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let safe = try await fixture.create()
    #expect(try await fixture.lifecycle.claim(safe))
    try await fixture.lifecycle.recover()
    #expect(try await fixture.state(safe) == .queued)
    let unknown = try await fixture.create()
    #expect(try await fixture.lifecycle.claim(unknown))
    let projection = try await fixture.repository.projection(identity: fixture.identity)
    let task = try #require(projection.tasks.first { $0.metadata.id == unknown })
    let source = try #require(projection.messages.first { $0.commandId == unknown })
    let recorder = WorkspaceResponseRecorder(repository: fixture.repository, identity: fixture.identity)
    let response = try await recorder.begin(id: UUID(), replyingTo: source, agentID: fixture.agentID)
    let steps = WorkspaceModelStepService(repository: fixture.repository, identity: fixture.identity), stepID = UUID()
    try await steps.begin(id: stepID, source: source, responseID: response.metadata.id, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
        modelID: "gigachat", configurationID: task.configurationId, taskID: unknown, budgetTokenLimit: 100_000)
    try await steps.finish(id: stepID, state: .waiting_tools, calls: [.init(id: "uncertain", name: "write", arguments: .object([:]))], usage: nil)
    try await recorder.recoverInterruptedResponses(); try await steps.recoverInterrupted(); try await fixture.lifecycle.recover()
    #expect(try await fixture.state(unknown) == .interrupted)
    await #expect(throws: WorkspaceTaskExecutionError.uncertainToolResult) { try await fixture.lifecycle.resume(commandID: UUID(), taskID: unknown) }
}

@Test func taskModelSetupFailureIsDurableAndDoesNotSpinTheQueue() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let id = try await fixture.create(), execution = try fixture.execution()
    await #expect(throws: ChatModelError.invalidConfiguration) {
        try await execution.run(taskID: id, makeModel: { _ in throw ChatModelError.invalidConfiguration })
    }
    #expect(try await fixture.state(id) == .failed)
}

@Test func recoveryAcceptsAnAlreadyRecordedFinalAnswerWithoutCallingTheModelAgain() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let id = try await fixture.create()
    #expect(try await fixture.lifecycle.claim(id))
    let projection = try await fixture.repository.projection(identity: fixture.identity)
    let source = try #require(projection.messages.first { $0.commandId == id }), task = try #require(projection.tasks.first)
    let recorder = WorkspaceResponseRecorder(repository: fixture.repository, identity: fixture.identity)
    let response = try await recorder.begin(id: UUID(), replyingTo: source, agentID: fixture.agentID)
    let steps = WorkspaceModelStepService(repository: fixture.repository, identity: fixture.identity), stepID = UUID()
    try await steps.begin(id: stepID, source: source, responseID: response.metadata.id, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
        modelID: "gigachat", configurationID: task.configurationId, taskID: id, budgetTokenLimit: 100_000)
    try await steps.finish(id: stepID, state: .completed, usage: nil)
    _ = try await recorder.finish(response.metadata.id, delivery: .completed, content: "Done")
    try await fixture.lifecycle.recover()
    #expect(try await fixture.state(id) == .completed)
    #expect(try await fixture.repository.projection(identity: fixture.identity).messages.count == 2)
}

@Test func verifiedUncertainActionCanContinueWithoutRepeatingTheExternalWrite() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let id = try await fixture.create()
    #expect(try await fixture.lifecycle.claim(id))
    let projection = try await fixture.repository.projection(identity: fixture.identity)
    let source = try #require(projection.messages.first { $0.commandId == id }), task = try #require(projection.tasks.first)
    let recorder = WorkspaceResponseRecorder(repository: fixture.repository, identity: fixture.identity)
    let response = try await recorder.begin(id: UUID(), replyingTo: source, agentID: fixture.agentID)
    let steps = WorkspaceModelStepService(repository: fixture.repository, identity: fixture.identity), stepID = UUID()
    let call = ChatToolCall(id: "external", name: "write", arguments: .object([:]))
    try await steps.begin(id: stepID, source: source, responseID: response.metadata.id, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
        modelID: "gigachat", configurationID: task.configurationId, taskID: id, budgetTokenLimit: 100_000)
    let permissions = WorkspacePermissionService(repository: fixture.repository, identity: fixture.identity)
    let actionID = WorkspaceToolCallIdentity.actionID(workspaceID: fixture.identity.workspaceID, sourceID: source.metadata.id, callID: call.id)
    _ = try await permissions.prepare(commandID: actionID, taskID: id, draft: .init(toolID: "write", resource: "synthetic", parametersJSON: "{}", consequences: "Test only"), expiresAt: Date().addingTimeInterval(600))
    let action = try #require(try await fixture.repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: fixture.identity.workspaceID))
    _ = try await permissions.approve(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version, digest: action.digest)
    let invocation = try await permissions.begin(actionID: actionID, digest: action.digest)
    try await permissions.finish(commandID: UUID(), invocationID: invocation.resultID, state: .unknown)
    try await steps.finish(id: stepID, state: .interrupted, calls: [call], results: [call.id: .object(["state": .string("unknown")])], usage: nil)
    _ = try await recorder.finish(response.metadata.id, delivery: .interrupted)
    try await fixture.lifecycle.recover()
    await #expect(throws: WorkspaceTaskExecutionError.uncertainToolResult) { try await fixture.lifecycle.resume(commandID: UUID(), taskID: id) }
    try await permissions.finish(commandID: UUID(), invocationID: invocation.resultID, state: .succeeded, result: "{\"state\":\"verified_by_user\",\"succeeded\":true}")
    try await WorkspaceTaskService(repository: fixture.repository, identity: fixture.identity).completeActionTask(taskID: id)
    #expect(try await fixture.state(id) == .interrupted)
    try await fixture.lifecycle.resume(commandID: UUID(), taskID: id)
    let tool = TaskWriteTool()
    try await fixture.execution(tool: tool).run(taskID: id, model: TaskModel([[.toolCall(.init(id: "repeat", name: "write", arguments: .object([:]))), .finished(.toolCalls)], [.text("Done"), .finished(.stop)]]))
    #expect(await tool.count == 0)
    #expect(try await fixture.state(id) == .completed)
}

@Test func legacyActionBookkeepingDoesNotBecomeANewExecutableTask() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let legacy = try await fixture.create()
    _ = try await WorkspacePermissionService(repository: fixture.repository, identity: fixture.identity).prepare(commandID: UUID(), taskID: legacy,
        draft: .init(toolID: "write", resource: "synthetic", parametersJSON: "{}", consequences: "Already prepared"), expiresAt: Date().addingTimeInterval(600))
    let runnable = try await fixture.create(), model = TaskModel([]), execution = try fixture.execution()
    let queue = WorkspaceTaskQueue(repository: fixture.repository, identity: fixture.identity, execute: { try await execution.run(taskID: $0, model: model) })
    await queue.start()
    try await waitForTask { try await fixture.state(runnable) == .completed }
    await queue.stop()
    #expect(try await fixture.state(legacy) == .queued)
    #expect(await model.count == 1)
}

@Test func pauseBeforeApprovalDoesNotLeaveAnUnresolvableUnknownAction() async throws {
    let fixture = try await TaskFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let id = try await fixture.create()
    #expect(try await fixture.lifecycle.claim(id))
    let projection = try await fixture.repository.projection(identity: fixture.identity)
    let source = try #require(projection.messages.first { $0.commandId == id }), task = try #require(projection.tasks.first)
    let call = ChatToolCall(id: "not-started", name: "write", arguments: .object([:]))
    let actionID = WorkspaceToolCallIdentity.actionID(workspaceID: fixture.identity.workspaceID, sourceID: source.metadata.id, callID: call.id)
    _ = try await WorkspacePermissionService(repository: fixture.repository, identity: fixture.identity).prepare(commandID: actionID, taskID: id,
        draft: .init(toolID: "write", resource: "synthetic", parametersJSON: "{}", consequences: "Awaiting approval"), expiresAt: Date().addingTimeInterval(600))
    let recorder = WorkspaceResponseRecorder(repository: fixture.repository, identity: fixture.identity)
    let response = try await recorder.begin(id: UUID(), replyingTo: source, agentID: fixture.agentID)
    let steps = WorkspaceModelStepService(repository: fixture.repository, identity: fixture.identity), stepID = UUID()
    try await steps.begin(id: stepID, source: source, responseID: response.metadata.id, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
        modelID: "gigachat", configurationID: task.configurationId, taskID: id, budgetTokenLimit: 100_000)
    try await steps.finish(id: stepID, state: .canceled, calls: [call], usage: nil)
    _ = try await recorder.finish(response.metadata.id, delivery: .canceled)
    try await fixture.lifecycle.pause(commandID: UUID(), taskID: id)
    try await fixture.lifecycle.resume(commandID: UUID(), taskID: id)
    let tool = TaskWriteTool()
    try await fixture.execution(tool: tool).run(taskID: id, model: TaskModel([[.toolCall(.init(id: "new-approved-attempt", name: "write", arguments: .object([:]))), .finished(.toolCalls)], [.text("Done"), .finished(.stop)]]))
    #expect(await tool.writes == 1)
    #expect(try await fixture.state(id) == .completed)
}
