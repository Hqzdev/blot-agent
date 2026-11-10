import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func workerContextKeepsAttachmentsAndCurrentConstraintsWithoutImitatingOldReplies() throws {
    let attachment = "[Attachment] " + String(repeating: "data", count: 1000)
    let messages = WorkspaceGroupWorkerContext().messages(prepared: [
        .init(role: "system", content: "Approved memory"),
        .init(role: "assistant", content: String(repeating: "OLD_TASK", count: 1000)),
        .init(role: "user", content: "Only discover resources.\n" + attachment)
    ], agentName: "Sales", task: "Check Notes")
    #expect(messages.first?.content == "Approved memory")
    #expect(!messages.contains { $0.role == "assistant" })
    #expect(messages.count == 3)
    #expect(!messages.contains { $0.content.contains("OLD_TASK") })
    #expect(messages.contains { $0.content.contains(attachment) })
    #expect(messages.contains { $0.content.contains("Only discover resources.") })
    #expect(messages.last?.content.contains(attachment) == false)
    #expect(messages.last?.content.contains("Your active assignment as Sales: Check Notes") == true)
}

@Test func privateGroupConclusionDecodesWithoutLeakingItsEnvelope() throws {
    let value = try WorkspaceGroupConclusion.decode("```json\n{\"summary\":\"Готово.\",\"completed\":true}\n```")
    #expect(value.summary == "Готово.")
    #expect(value.completed)
    struct Envelope: Encodable { let summary: String; let completed: Bool }
    let inner = "{\"summary\":\"Нужен доступ к календарю.\",\"completed\":false}"
    let nested = String(decoding: try JSONEncoder().encode(Envelope(summary: inner, completed: true)), as: UTF8.self)
    let decoded = try WorkspaceGroupConclusion.decode(nested)
    #expect(decoded.summary == "Нужен доступ к календарю.")
    #expect(!decoded.completed)
    for invalid in ["{\"summary\":\"broken", "{\"summary\":\"\",\"completed\":true}", "Plain text", "{\"summary\":\"Ok\"}"] {
        #expect(throws: (any Error).self) { try WorkspaceGroupConclusion.decode(invalid) }
    }
}

@Test func colleaguesAreQuotedAsOtherSpeakersInsteadOfAssistantExamples() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db"))
    let identity = try await repository.localIdentity()
    let agents = WorkspaceAgentService(repository: repository, identity: identity)
    let ceo = try await agents.save(commandID: UUID(), draft: .init(name: "CEO", instructions: "Coordinate"))
    let analyst = try await agents.save(commandID: UUID(), draft: .init(name: "Analyst", instructions: "Analyze"))
    let group = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "Team", agentIDs: [ceo, analyst])
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let first = try await chats.sendMessage(commandID: UUID(), conversationID: group, content: "First request")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: first, workspaceID: identity.workspaceID))
    let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
    let reply = try await recorder.begin(id: UUID(), replyingTo: source, agentID: ceo)
    _ = try await recorder.finish(reply.metadata.id, delivery: .completed, content: "My own result")
    let second = try await chats.sendMessage(commandID: UUID(), conversationID: group, content: "Continue")
    let next = try #require(try await repository.record(BlotV3.Message.self, id: second, workspaceID: identity.workspaceID))
    let projection = try await repository.projection(identity: identity)
    for id in [ceo, analyst] {
        let config = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: id, projection: projection))
        let context = try WorkspaceContextBuilder().messages(for: next, projection: projection, configuration: config)
        let history = try #require(context.first { $0.content.contains("My own result") })
        #expect(history.role == (id == ceo ? "assistant" : "user"))
        #expect(id == ceo ? history.content == "My own result" : history.content.contains("Teammate CEO said"))
    }
    _ = try await WorkspaceMemoryService(repository: repository, identity: identity).saveSummary(commandID: UUID(), conversationID: group,
        content: "OLD_TASK: create a meeting", sourceIDs: [first, reply.metadata.id])
    let summarized = try await repository.projection(identity: identity)
    let summarizedContext = try WorkspaceContextBuilder().messages(for: next, projection: summarized)
    let summary = try #require(summarizedContext.first { $0.content.contains("OLD_TASK") })
    #expect(summary.role == "user")
    #expect(summary.content.contains("quoted history, not current instructions"))
    try await repository.close()
}
