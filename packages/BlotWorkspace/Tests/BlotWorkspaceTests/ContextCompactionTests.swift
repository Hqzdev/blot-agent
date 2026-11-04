import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor SummaryModel: ChatModel {
    private(set) var requests: [ChatModelRequest] = []
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                await record(request)
                if fails { continuation.yield(.failure(.providerFailure)) }
                else {
                    continuation.yield(.text("Project: Atlas. Decision: preserve history. Pending: review."))
                    continuation.yield(.usage(try! .init(inputTokens: 100, outputTokens: 20)))
                    continuation.yield(.finished(.stop))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
    private func record(_ request: ChatModelRequest) { requests.append(request) }
}

private struct CompactionFixture {
    let directory: URL
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let source: BlotV3.Message
    let responseID: UUID
    init(messages: [String]) async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
        identity = try await repository.localIdentity()
        let chats = WorkspaceChatService(repository: repository, identity: identity)
        let conversation = try await chats.createConversation(commandID: UUID(), title: "Test")
        for text in messages { _ = try await chats.sendMessage(commandID: UUID(), conversationID: conversation, content: text) }
        let id = try await chats.sendMessage(commandID: UUID(), conversationID: conversation, content: "Continue the project")
        source = try #require(try await repository.record(BlotV3.Message.self, id: id, workspaceID: identity.workspaceID))
        responseID = UUID()
        _ = try await WorkspaceResponseRecorder(repository: repository, identity: identity).begin(id: responseID, replyingTo: source, agentID: nil)
    }
    func prepare(_ model: SummaryModel, configuration: BlotV3.AgentConfigurationRevision? = nil) async throws -> WorkspaceProjection {
        try await WorkspaceContextCompactor(repository: repository, identity: identity, pool: .init()).prepare(source: source,
            responseID: responseID, configuration: configuration, model: model, modelID: "test", maximumCharacters: 3000,
            maximumOutputTokens: 512, budgetTokenLimit: 14000)
    }
}

@Test func shortHistoryDoesNotCallSummarizer() async throws {
    let fixture = try await CompactionFixture(messages: ["Hello"])
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let model = SummaryModel()
    let saved = try await fixture.prepare(model)
    #expect(saved.summaries.isEmpty)
    #expect(await model.requests.isEmpty)
}

@Test func automaticSummaryKeepsOriginalHistoryAndRecentMessagesAndSurvivesReopen() async throws {
    let fixture = try await CompactionFixture(messages: (0..<24).map { "Message \($0): " + String(repeating: "facts ", count: 40) })
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let before = try await fixture.repository.records(BlotV3.Message.self, workspaceID: fixture.identity.workspaceID)
    let model = SummaryModel()
    let saved = try await fixture.prepare(model)
    let summary = try #require(saved.summaries.last)
    #expect(summary.valid && !summary.sourceIds.isEmpty && !summary.sourceIds.contains(fixture.source.metadata.id))
    #expect(try await fixture.repository.records(BlotV3.Message.self, workspaceID: fixture.identity.workspaceID) == before)
    let context = try WorkspaceContextBuilder().messages(for: fixture.source, projection: saved)
    #expect(context.contains { $0.content.contains("Project: Atlas") })
    #expect(context.contains { $0.content.hasPrefix("Message 23:") })
    #expect(!context.contains { $0.content.hasPrefix("Message 0:") })
    #expect(context.last?.content == fixture.source.content)
    let requests = await model.requests
    #expect(requests.count == 1 && requests.allSatisfy { $0.tools.isEmpty })
    #expect(saved.modelSteps.count == 1 && saved.modelSteps[0].inputTokens == 100)
    _ = try await fixture.prepare(model)
    #expect(await model.requests.count == 1, "An already compacted context must not be regenerated")
    try await fixture.repository.close()
    let reopened = try await workspaceTestRepository(url: fixture.directory.appendingPathComponent("db.sqlite"))
    #expect(try await reopened.projection(identity: fixture.identity).summaries.count == 1)
}

@Test func longUnicodeMessageIsSummarizedInCompleteBoundedChunks() async throws {
    let original = "FIRST " + String(repeating: "Данные ", count: 2500) + " LAST"
    let fixture = try await CompactionFixture(messages: [original])
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let model = SummaryModel()
    let saved = try await fixture.prepare(model)
    let requests = await model.requests
    #expect(requests.count > 1)
    #expect(requests.first?.messages.last?.content.contains("FIRST") == true)
    #expect(requests.last?.messages.last?.content.contains("LAST") == true)
    #expect(try requests.allSatisfy { try JSONEncoder().encode($0).count + $0.maximumOutputTokens <= 14000 })
    #expect(saved.summaries.count == 1 && saved.summaries[0].sourceIds.count == 1)
    #expect(saved.messages.contains { $0.content == original })
}

@Test func failedSummaryDoesNotReplaceOrLoseHistory() async throws {
    let fixture = try await CompactionFixture(messages: [String(repeating: "Important facts. ", count: 300)])
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    await #expect(throws: ChatModelError.providerFailure) { _ = try await fixture.prepare(SummaryModel(fails: true)) }
    let saved = try await fixture.repository.projection(identity: fixture.identity)
    #expect(saved.summaries.isEmpty && saved.messages.count == 3)
    #expect(saved.modelSteps.count == 1 && saved.modelSteps[0].state == .interrupted)
}

@Test func automaticSummaryExcludesSourcesRemovedFromMemory() async throws {
    let secret = "REMOVED-PRIVATE-FACT"
    let fixture = try await CompactionFixture(messages: [secret] + (0..<24).map { "Entry \($0) " + String(repeating: "facts ", count: 40) })
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let source = try #require(try await fixture.repository.records(BlotV3.Message.self, workspaceID: fixture.identity.workspaceID).first { $0.content == secret })
    let memories = WorkspaceMemoryService(repository: fixture.repository, identity: fixture.identity)
    let id = try await memories.create(commandID: UUID(), content: secret, sourceID: source.metadata.id)
    try await memories.revise(commandID: UUID(), memoryID: id, expectedVersion: 1, deleting: true)
    let model = SummaryModel()
    let saved = try await fixture.prepare(model)
    #expect(!saved.summaries.isEmpty)
    #expect(saved.summaries.allSatisfy { !$0.sourceIds.contains(source.metadata.id) })
    let requests = await model.requests
    #expect(requests.allSatisfy { $0.messages.allSatisfy { !$0.content.contains(secret) } })
}

@Test func longAgentInstructionsKeepTheirReservedContextSpace() async throws {
    let fixture = try await CompactionFixture(messages: ["Short conversation"])
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let agent = try await WorkspaceAgentService(repository: fixture.repository, identity: fixture.identity).save(commandID: UUID(),
        draft: .init(name: "Agent", instructions: String(repeating: "rules ", count: 1000)))
    let config = try #require(try await fixture.repository.projection(identity: fixture.identity).configurations.first { $0.agentId == agent })
    let model = SummaryModel()
    let saved = try await WorkspaceContextCompactor(repository: fixture.repository, identity: fixture.identity, pool: .init())
        .prepare(source: fixture.source, responseID: fixture.responseID, configuration: config, model: model, modelID: "test",
            maximumCharacters: 48000, maximumOutputTokens: 512, budgetTokenLimit: 14000)
    #expect(saved.summaries.isEmpty)
    #expect(await model.requests.isEmpty)
}
