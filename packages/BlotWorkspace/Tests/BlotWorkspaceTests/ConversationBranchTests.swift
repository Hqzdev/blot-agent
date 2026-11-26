import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func branchesStaySeparateAndCopyOnlyTheSelectedDialoguePrefix() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
    let identity = try await repository.localIdentity()
    let agents = WorkspaceAgentService(repository: repository, identity: identity)
    let first = try await agents.save(commandID: UUID(), draft: .init(name: "Author", instructions: "Help"))
    let second = try await agents.save(commandID: UUID(), draft: .init(name: "Reviewer", instructions: "Review"))
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let sourceChat = try await chats.createConversation(commandID: UUID(), title: "Author", agentID: first)
    let existing = try await chats.createConversation(commandID: UUID(), title: "Reviewer", agentID: second)
    let user = try await chats.sendMessage(commandID: UUID(), conversationID: sourceChat, content: "Test budget 45000")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: user, workspaceID: identity.workspaceID))
    let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
    let answer = UUID()
    _ = try await recorder.begin(id: answer, replyingTo: source, agentID: first)
    _ = try await recorder.finish(answer, delivery: .completed, content: "Verified: 45000")
    _ = try await chats.sendMessage(commandID: UUID(), conversationID: sourceChat, content: "Later private context must not move")
    let command = UUID(), brancher = WorkspaceConversationBranch(repository: repository, identity: identity)
    #expect(try await brancher.create(commandID: command, messageID: answer, agentID: second) == command)
    #expect(try await brancher.create(commandID: command, messageID: answer, agentID: second) == command)
    let snapshot = try await repository.projection(identity: identity)
    #expect(snapshot.conversations.count == 3)
    let branch = try #require(snapshot.conversations.first { $0.metadata.id == command })
    #expect(branch.agentId == second && branch.parentMessageId == answer && branch.parentConversationId == sourceChat)
    #expect(branch.kind == .group, "Older clients must keep branches separate from canonical agent chats")
    #expect(snapshot.participants.filter { $0.conversationId == command && $0.kind == .agent && !$0.removed }.map(\.participantId) == [second])
    let copied = WorkspaceMessageOrder.ordered(snapshot.messages.filter { $0.conversationId == command })
    #expect(copied.map(\.content) == ["Test budget 45000", "Verified: 45000"])
    #expect(copied[1].replyToMessageId == copied[0].metadata.id)
    #expect(copied.allSatisfy { $0.metadata.id != user && $0.metadata.id != answer })
    #expect(snapshot.messages.filter { $0.conversationId == existing }.isEmpty)
    #expect(snapshot.modelSteps.isEmpty && snapshot.actions.isEmpty && snapshot.invocations.isEmpty)
    #expect(try await chats.createConversation(commandID: UUID(), title: "Reviewer", agentID: second) == existing)
    try await WorkspaceConversationService(repository: repository, identity: identity).update(commandID: UUID(), conversationID: command,
        expectedVersion: branch.metadata.version, title: "Review branch", pinned: true)
    let updated = try await repository.projection(identity: identity)
    #expect(updated.conversations.first { $0.metadata.id == command }?.parentMessageId == answer)
    let renamed = try #require(updated.conversations.first { $0.metadata.id == command })
    try await WorkspaceGroupService(repository: repository, identity: identity).update(commandID: UUID(), conversationID: command,
        expectedVersion: renamed.metadata.version, title: "Renamed branch", agentIDs: [second])
    let edited = try await repository.projection(identity: identity)
    #expect(edited.conversations.first { $0.metadata.id == command }?.parentMessageId == answer)
    #expect(edited.conversations.first { $0.metadata.id == command }?.parentConversationId == sourceChat)
    let original = try #require(updated.conversations.first { $0.metadata.id == sourceChat })
    try await WorkspaceConversationService(repository: repository, identity: identity).delete(commandID: UUID(), conversationID: sourceChat, expectedVersion: original.metadata.version)
    let retained = try await repository.projection(identity: identity)
    #expect(retained.messages.filter { $0.conversationId == command }.count == 2)
}
