import BlotDomain
import Foundation
import Synchronization
import Testing
@testable import BlotWorkspace

private final class ReplyEvents: Sendable {
    private let storage = Mutex<[BlotV3.Message]>([])
    var messages: [BlotV3.Message] { storage.withLock { $0 } }
    func append(_ message: BlotV3.Message) { storage.withLock { $0.append(message) } }
}

private actor ReplyModel: ChatModel {
    private var turns: [[ChatModelEvent]]
    private(set) var requests: [ChatModelRequest] = []
    init(_ turns: [[ChatModelEvent]]) { self.turns = turns }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                for event in await next(request) { continuation.yield(event) }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
    private func next(_ request: ChatModelRequest) -> [ChatModelEvent] { requests.append(request); return turns.removeFirst() }
}

private struct ReplyTool: WorkspaceToolExecuting {
    let beforeExecution: @Sendable () async throws -> Void
    private let output: ChatJSON
    init(beforeExecution: @escaping @Sendable () async throws -> Void, output: ChatJSON = .object(["result": .string("checked")])) {
        self.beforeExecution = beforeExecution; self.output = output
    }
    let definitions = [ChatToolDefinition(name: "inspect", description: "Inspect the requested item", parameters:
        .object(["type": .string("object"), "properties": .object([:])]))]
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        try await beforeExecution()
        return output
    }
}

private struct ReplyFixture {
    let directory: URL
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let configuration: BlotV3.AgentConfigurationRevision
    let source: BlotV3.Message
    let responseID: UUID

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
        identity = try await repository.localIdentity()
        let agentID = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Agent", instructions: "Help the user", modelID: "gigachat", toolIDs: ["inspect"]))
        configuration = try #require(try await repository.projection(identity: identity).configurations.first)
        let chat = WorkspaceChatService(repository: repository, identity: identity)
        let conversationID = try await chat.createConversation(commandID: UUID(), title: "Test", agentID: agentID)
        let messageID = try await chat.sendMessage(commandID: UUID(), conversationID: conversationID, content: "Inspect this")
        source = try #require(try await repository.record(BlotV3.Message.self, id: messageID, workspaceID: identity.workspaceID))
        responseID = UUID()
        _ = try await WorkspaceResponseRecorder(repository: repository, identity: identity).begin(id: responseID, replyingTo: source, agentID: agentID)
    }

    func run(_ model: any ChatModel, tool: ReplyTool, events: ReplyEvents, firstToolID: String? = nil, messages: [ChatModelMessage]? = nil, resolvedContext: String? = nil, operations: [WorkspaceToolOperation] = [], budgetTokenLimit: Int = 10000) async throws {
        let runtime = WorkspaceModelRuntime(repository: repository, identity: identity, pool: .init(), tools: try .init(providers: [tool]))
        try await runtime.generate(source: source, responseID: responseID,
            request: .init(messages: messages ?? [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
            model: model, modelID: "gigachat", configuration: configuration, budgetTokenLimit: budgetTokenLimit, firstToolID: firstToolID, resolvedContext: resolvedContext, operations: operations,
            emit: { events.append($0) })
    }
}

@Test func modelDeltasPublishOneWholeDurableReplyWithoutSplittingParagraphs() async throws {
    let fixture = try await ReplyFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let events = ReplyEvents()
    let text = "First paragraph.\n\nSecond paragraph."
    try await fixture.run(ReplyModel([[.text("First "), .text("paragraph.\n\n"), .text("Second paragraph."), .finished(.stop)]]),
        tool: .init(beforeExecution: {}), events: events)
    #expect(events.messages.count == 1)
    let reply = try #require(events.messages.first)
    #expect(reply.content == text && reply.delivery == .completed)
    let persisted = try #require(try await fixture.repository.record(BlotV3.Message.self, id: reply.metadata.id, workspaceID: fixture.identity.workspaceID))
    #expect(persisted == reply)
    #expect(persisted.metadata.version == 2, "Chunks must not cause individual storage writes")
}

@Test func acknowledgementIsDurableBeforeToolAndResultArrivesAsSecondMessage() async throws {
    let fixture = try await ReplyFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let events = ReplyEvents()
    let model = ReplyModel([
        [.text("I'll "), .text("check."), .toolCall(.init(id: "one", name: "inspect", arguments: .object([:]))), .finished(.toolCalls)],
        [.text("Checked. "), .text("Here is the result."), .finished(.stop)]
    ])
    try await fixture.run(model, tool: .init(beforeExecution: {
        let saved = try await fixture.repository.projection(identity: fixture.identity)
        let acknowledgement = try #require(saved.messages.first { $0.metadata.id == fixture.responseID })
        #expect(acknowledgement.content == "I'll check." && acknowledgement.delivery == .completed)
        #expect(saved.messages.filter { $0.role == .assistant && $0.delivery == .running }.count == 1)
        #expect(events.messages.filter { $0.delivery == .completed }.map(\.content) == ["I'll check."])
    }), events: events)
    let saved = try await fixture.repository.projection(identity: fixture.identity)
    let replies = WorkspaceMessageOrder.ordered(saved.messages.filter { $0.role == .assistant })
    #expect(replies.map(\.content) == ["I'll check.", "Checked. Here is the result."])
    #expect(replies.allSatisfy { $0.delivery == .completed && $0.replyToMessageId == fixture.source.metadata.id })
    #expect(Set(saved.modelSteps.map(\.responseMessageId)) == Set(replies.map(\.metadata.id)))
    #expect(events.messages.filter { $0.delivery == .running }.allSatisfy { $0.content.isEmpty })
    try await fixture.repository.close()
    let reopened = try await workspaceTestRepository(url: fixture.directory.appendingPathComponent("db.sqlite"))
    #expect(try await reopened.records(BlotV3.Message.self, workspaceID: fixture.identity.workspaceID).filter { $0.role == .assistant }.count == 2)
}

@Test func failedContinuationLeavesAcknowledgementCompletedAndEndsOnlyCurrentReply() async throws {
    let fixture = try await ReplyFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let events = ReplyEvents()
    await #expect(throws: ChatModelError.providerFailure) {
        try await fixture.run(ReplyModel([
            [.text("I'll check."), .toolCall(.init(id: "one", name: "inspect", arguments: .object([:]))), .finished(.toolCalls)],
            [.text("Partial result"), .failure(.providerFailure)]
        ]), tool: .init(beforeExecution: {}), events: events)
    }
    let saved = try await fixture.repository.projection(identity: fixture.identity)
    let replies = WorkspaceMessageOrder.ordered(saved.messages.filter { $0.role == .assistant })
    #expect(replies.count == 2)
    #expect(replies[0].content == "I'll check." && replies[0].delivery == .completed)
    #expect(replies[1].content == "Partial result" && replies[1].delivery == .interrupted)
    #expect(!saved.messages.contains { $0.delivery == .running })
    #expect(events.messages.allSatisfy { $0.delivery != .running || $0.content.isEmpty })
}

@Test func requiredFirstToolRejectsSimulatedSuccessAndUnassignedTools() async throws {
    let fixture = try await ReplyFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let events = ReplyEvents()
    let tool = ReplyTool(beforeExecution: { Issue.record("A text-only response must not execute a tool") })
    await #expect(throws: ChatModelError.invalidStream) {
        try await fixture.run(ReplyModel([[.text("Использование функции... Всё создано."), .finished(.stop)]]), tool: tool, events: events, firstToolID: "inspect")
    }
    #expect(events.messages.allSatisfy { $0.content.isEmpty && $0.delivery != .completed })
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        try await fixture.run(ReplyModel([]), tool: tool, events: events, firstToolID: "not_assigned")
    }
}

@Test func newToolWorkUsesResolvedAssignmentAndBuildsFreshFunctionHistory() async throws {
    let fixture = try await ReplyFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let model = ReplyModel([
        [.toolCall(.init(id: "fresh", name: "inspect", arguments: .object([:]))), .finished(.toolCalls)],
        [.text("Checked."), .finished(.stop)]
    ])
    try await fixture.run(model, tool: .init(beforeExecution: {}), events: ReplyEvents(), firstToolID: "inspect", messages: [
        .init(role: "user", content: "Old request"),
        .init(role: "assistant", content: "Использование функции... Всё создано.", toolCalls: [.init(id: "old", name: "removed_tool", arguments: .object([:]))]),
        .init(role: "user", content: fixture.source.content)
    ], resolvedContext: "Target: file.md. Read only.")
    let requests = await model.requests
    #expect(requests.count == 2 && requests[0].requiredTool == "inspect" && requests[1].requiredTool == nil)
    #expect(requests[0].messages.last?.content.contains(fixture.source.content) == true)
    #expect(!requests[0].messages.contains { $0.role == "assistant" || !$0.toolCalls.isEmpty })
    #expect(requests[0].messages.contains { $0.role == "user" && $0.content.contains("Target: file.md") })
    #expect(!requests[0].messages.contains { $0.content.contains("Всё создано") || $0.content.contains("Old request") })
    #expect(requests[1].messages.contains { $0.role == "assistant" && $0.toolCalls.map(\.id) == ["fresh"] })
    #expect(requests[1].messages.contains { $0.role == "tool" && $0.toolCallID == "fresh" })
}

@Test func plannedOperationsRequireEveryStageBeforeFinalText() async throws {
    let fixture = try await ReplyFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let counter = Mutex(0)
    let model = ReplyModel([
        [.toolCall(.init(id: "first", name: "inspect", arguments: .object([:]))), .finished(.toolCalls)],
        [.toolCall(.init(id: "second", name: "inspect", arguments: .object([:]))), .finished(.toolCalls)],
        [.text("Both inspected."), .finished(.stop)]
    ])
    try await fixture.run(model, tool: .init(beforeExecution: { counter.withLock { $0 += 1 } }), events: ReplyEvents(), operations: [
        .init(toolID: "inspect", instruction: "Inspect first item"), .init(toolID: "inspect", instruction: "Inspect second item")
    ], budgetTokenLimit: 20000)
    let requests = await model.requests
    #expect(counter.withLock { $0 } == 2)
    #expect(requests.map(\.requiredTool) == ["inspect", "inspect", nil])
    #expect(requests[1].messages.contains { $0.role == "system" && $0.content.contains("Inspect second item") })
    let saved = try await fixture.repository.projection(identity: fixture.identity)
    #expect(saved.messages.filter { $0.role == .assistant && $0.delivery == .completed }.count == 3)
}

@Test func failedPlannedOperationCannotTriggerTheNextEffectOrRetry() async throws {
    let fixture = try await ReplyFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let counter = Mutex(0)
    let model = ReplyModel([
        [.toolCall(.init(id: "first", name: "inspect", arguments: .object([:]))), .finished(.toolCalls)],
        [.toolCall(.init(id: "retry", name: "inspect", arguments: .object([:]))), .finished(.toolCalls)]
    ])
    await #expect(throws: ChatModelError.invalidStream) {
        try await fixture.run(model, tool: .init(beforeExecution: { counter.withLock { $0 += 1 } }, output: .object(["state": .string("failed"), "error": .string("Fixture refusal")])), events: ReplyEvents(), operations: [
            .init(toolID: "inspect", instruction: "First operation"), .init(toolID: "inspect", instruction: "Dependent operation")
        ])
    }
    #expect(counter.withLock { $0 } == 1)
    let saved = try await fixture.repository.projection(identity: fixture.identity)
    #expect(saved.modelSteps.contains { $0.toolResultsJSON?.contains("Fixture refusal") == true })
}
