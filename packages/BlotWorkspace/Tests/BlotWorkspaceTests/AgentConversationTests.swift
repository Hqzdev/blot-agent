import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func reopeningAnAgentReusesItsChatAndUnarchivesIt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
        draft: .init(name: "Agent", instructions: "Help"))
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let id = try await chats.createConversation(commandID: UUID(), title: "Agent", agentID: agent)
    for _ in 0..<20 { #expect(try await chats.createConversation(commandID: UUID(), title: "Agent", agentID: agent) == id) }
    let original = try #require(try await repository.record(BlotV3.Conversation.self, id: id, workspaceID: identity.workspaceID))
    try await WorkspaceConversationService(repository: repository, identity: identity).update(commandID: UUID(),
        conversationID: id, expectedVersion: original.metadata.version, archived: true)
    #expect(try await chats.createConversation(commandID: UUID(), title: "Agent", agentID: agent) == id)
    let saved = try await repository.projection(identity: identity)
    #expect(saved.conversations.count == 1 && !saved.conversations[0].archived)
}

@Test func legacyAgentThreadsCombineWithoutRewritingOrLosingMessages() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Agent", instructions: "Help"))
    let first = UUID(), second = UUID(), group = UUID()
    _ = try await repository.execute(commandID: UUID(), command: Data("legacy fixture".utf8), identity: identity) { tx in
        for (index, id) in [first, second, group].enumerated() {
            let chat = try BlotV3.Conversation(metadata: tx.metadata(id: id, now: Date(timeIntervalSince1970: Double(index))),
                agentId: agent, title: "Agent", mobileOwned: false, pinned: id == second, archived: id == first,
                kind: id == group ? .group : .direct)
            try tx.put(chat, expectedVersion: 0)
        }
        return first
    }
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let one = try await chats.sendMessage(commandID: UUID(), conversationID: first, content: "First", now: Date(timeIntervalSince1970: 10))
    let two = try await chats.sendMessage(commandID: UUID(), conversationID: second, content: "Second", now: Date(timeIntervalSince1970: 20))
    let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
    let source = try #require(try await repository.record(BlotV3.Message.self, id: two, workspaceID: identity.workspaceID))
    let replyID = UUID()
    _ = try await recorder.begin(id: replyID, replyingTo: source, agentID: agent, now: Date(timeIntervalSince1970: 21))
    _ = try await recorder.finish(replyID, delivery: .completed, content: "Answer", now: Date(timeIntervalSince1970: 22))
    let reply = try #require(try await repository.record(BlotV3.Message.self, id: replyID, workspaceID: identity.workspaceID))
    try await WorkspaceInteractionService(repository: repository, identity: identity).markRead(commandID: UUID(), conversationID: first, messageID: replyID)
    let saved = try await repository.projection(identity: identity)
    #expect(saved.conversations.count == 2, "A group must remain separate")
    #expect(saved.conversations.first { $0.metadata.id == first }?.pinned == true)
    #expect(saved.conversations.first { $0.metadata.id == first }?.archived == false)
    let merged = WorkspaceMessageOrder.ordered(saved.messages.filter { $0.conversationId == first })
    #expect(merged.map(\.metadata.id) == [one, two, replyID])
    #expect(merged.map(\.position) == [1, 2, 3])
    #expect(merged.last?.replyToMessageId == two)
    #expect(saved.readPositions.first?.position == 3)
    #expect(try await repository.record(BlotV3.Message.self, id: replyID, workspaceID: identity.workspaceID) == reply,
        "Foreign executor records must never be rewritten just to combine a chat")
    _ = try await chats.sendMessage(commandID: UUID(), conversationID: first, content: "Quoted", replyToMessageID: two)
    let current = try #require(try await repository.record(BlotV3.Conversation.self, id: first, workspaceID: identity.workspaceID))
    try await WorkspaceConversationService(repository: repository, identity: identity).update(commandID: UUID(),
        conversationID: first, expectedVersion: current.metadata.version, pinned: false, archived: true)
    let archived = try await repository.projection(identity: identity)
    #expect(archived.conversations.first { $0.metadata.id == first }?.archived == true)
    #expect(archived.conversations.first { $0.metadata.id == first }?.pinned == false)
    try await repository.close()
    let reopened = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
    let restored = try await reopened.projection(identity: identity)
    #expect(restored.messages.count == 4 && restored.conversations.count == 2)
    let deleting = try #require(restored.conversations.first { $0.metadata.id == first })
    try await WorkspaceConversationService(repository: reopened, identity: identity).delete(commandID: UUID(),
        conversationID: first, expectedVersion: deleting.metadata.version)
    let deleted = try await reopened.projection(identity: identity)
    #expect(deleted.messages.isEmpty && deleted.conversations.map(\.metadata.id) == [group])
}
