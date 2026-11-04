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
    init(_ turns: [[ChatModelEvent]]) { self.turns = turns }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                for event in await next() { continuation.yield(event) }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
    private func next() -> [ChatModelEvent] { turns.removeFirst() }
}

private struct ReplyTool: WorkspaceToolExecuting {
    let beforeExecution: @Sendable () async throws -> Void
    let definitions = [ChatToolDefinition(name: "inspect", description: "Inspect the requested item", parameters:
        .object(["type": .string("object"), "properties": .object([:])]))]
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        try await beforeExecution()
        return .object(["result": .string("checked")])
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

    func run(_ model: any ChatModel, tool: ReplyTool, events: ReplyEvents) async throws {
        let runtime = WorkspaceModelRuntime(repository: repository, identity: identity, pool: .init(), tools: try .init(providers: [tool]))
        try await runtime.generate(source: source, responseID: responseID,
            request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
            model: model, modelID: "gigachat", configuration: configuration, budgetTokenLimit: 10000,
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
