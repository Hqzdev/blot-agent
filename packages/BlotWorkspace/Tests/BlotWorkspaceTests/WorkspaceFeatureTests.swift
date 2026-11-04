import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct FeatureWorkspace {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var url: URL { directory.appendingPathComponent("workspace.sqlite") }
    func clean() { cleanupWorkspaceTestStorage(directory) }
}

@Test func agentRevisionsAreImmutableAndConcurrentEditsConflict() async throws {
    let files = FeatureWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let service = WorkspaceAgentService(repository: repository, identity: identity)
    let draft = WorkspaceAgentDraft(name: "Researcher", instructions: "Cite sources", toolIDs: ["files.read"])
    let command = UUID()
    let id = try await service.save(commandID: command, draft: draft)
    #expect(try await service.save(commandID: command, draft: draft) == id)
    _ = try await service.save(commandID: UUID(), agentID: id, expectedVersion: 1,
        draft: .init(name: "Researcher", instructions: "Compare sources"))
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        _ = try await service.save(commandID: UUID(), agentID: id, expectedVersion: 1, draft: draft)
    }
    let revisions = try await repository.records(BlotV3.AgentConfigurationRevision.self, workspaceID: identity.workspaceID)
    #expect(revisions.count == 2)
    #expect(revisions[0].instructions == "Cite sources" && revisions[0].toolIds == ["files.read"])
    #expect(revisions[1].instructions == "Compare sources")
    var projection = try await repository.projection(identity: identity)
    let resolver = WorkspaceAgentConfigurationResolver()
    #expect(try resolver.resolve(agentID: id, projection: projection)?.instructions == "Compare sources")
    let profile = try #require(projection.agents.first)
    projection.configurations.removeAll { $0.metadata.id == profile.configurationId }
    #expect(throws: WorkspaceStorageError.missingRecord) {
        try resolver.resolve(agentID: id, projection: projection)
    }
    #expect(try resolver.resolve(agentID: nil, projection: projection) == nil)
}

@Test func groupMembershipAndStructuredMentionsAreDurableAndEnforced() async throws {
    let files = FeatureWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let agents = WorkspaceAgentService(repository: repository, identity: identity)
    let agent = try await agents.save(commandID: UUID(), draft: .init(name: "Agent", instructions: "Check"))
    let groups = WorkspaceGroupService(repository: repository, identity: identity)
    let groupID = try await groups.create(commandID: UUID(), title: "Review", agentIDs: [agent])
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let mention = try BlotV3.MessageMention(agentId: agent, startUTF16: 0, lengthUTF16: 6)
    _ = try await chats.sendMessage(commandID: UUID(), conversationID: groupID, content: "@Agent check", mentions: [mention])
    try await groups.setAgent(commandID: UUID(), conversationID: groupID, agentID: agent, removed: true)
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        _ = try await chats.sendMessage(commandID: UUID(), conversationID: groupID, content: "@Agent check", mentions: [mention])
    }
    let reopened = try await workspaceTestRepository(url: files.url)
    #expect(try await reopened.records(BlotV3.Conversation.self, workspaceID: identity.workspaceID).first?.kind == .group)
    #expect(try await reopened.records(BlotV3.ConversationParticipant.self, workspaceID: identity.workspaceID).filter { !$0.removed }.count == 1)
    #expect(try await reopened.records(BlotV3.Message.self, workspaceID: identity.workspaceID).count == 1)
}

@Test func reactionsHaveStableLogicalKeysAndReadPositionNeverRewinds() async throws {
    let files = FeatureWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chats.createConversation(commandID: UUID(), title: "Read")
    let first = try await chats.sendMessage(commandID: UUID(), conversationID: conversation, content: "First")
    let second = try await chats.sendMessage(commandID: UUID(), conversationID: conversation, content: "Second")
    let interactions = WorkspaceInteractionService(repository: repository, identity: identity)
    try await interactions.setReaction(commandID: UUID(), messageID: first, emoji: "👍", removed: false)
    try await interactions.setReaction(commandID: UUID(), messageID: first, emoji: "👍", removed: false)
    try await interactions.setReaction(commandID: UUID(), messageID: first, emoji: "❤️", removed: false, replacingOtherReactions: true)
    try await interactions.markRead(commandID: UUID(), conversationID: conversation, messageID: second)
    try await interactions.markRead(commandID: UUID(), conversationID: conversation, messageID: first)
    let reopened = try await workspaceTestRepository(url: files.url)
    let reactions = try await reopened.records(BlotV3.MessageReaction.self, workspaceID: identity.workspaceID)
    #expect(reactions.count == 2 && reactions.filter { !$0.removed }.map(\.emoji) == ["❤️"])
    let read = try #require(try await reopened.records(BlotV3.ConversationReadPosition.self, workspaceID: identity.workspaceID).first)
    #expect(read.messageId == second && read.position == 2 && read.metadata.version == 1)
}

@Test func deletedMemoryInvalidatesSummariesAndCannotReturnFromItsSource() async throws {
    let files = FeatureWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chats.createConversation(commandID: UUID(), title: "Memory")
    let source = try await chats.sendMessage(commandID: UUID(), conversationID: conversation, content: "Private fact")
    let memories = WorkspaceMemoryService(repository: repository, identity: identity)
    let memory = try await memories.create(commandID: UUID(), content: "Private fact", sourceID: source, candidate: true)
    try await memories.revise(commandID: UUID(), memoryID: memory, expectedVersion: 1, accepting: true)
    _ = try await memories.saveSummary(commandID: UUID(), conversationID: conversation, content: "Private fact", sourceIDs: [source])
    try await memories.revise(commandID: UUID(), memoryID: memory, expectedVersion: 2, deleting: true)
    #expect(try await repository.records(BlotV3.ContextSummary.self, workspaceID: identity.workspaceID).allSatisfy { !$0.valid })
    let deleted = try #require(try await repository.record(BlotV3.MemoryEntry.self, id: memory, workspaceID: identity.workspaceID))
    #expect(deleted.state == .deleted && deleted.content.isEmpty)
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        _ = try await memories.saveSummary(commandID: UUID(), conversationID: conversation, content: "Old fact", sourceIDs: [source])
    }
    await #expect(throws: WorkspaceStorageError.deletedRecord) {
        try await memories.revise(commandID: UUID(), memoryID: memory, expectedVersion: 3, accepting: true)
    }
}

@Test func skillVersionsKeepOriginalParametersAndDoNotRecursivelySubstituteInput() async throws {
    let files = FeatureWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let skills = WorkspaceSkillService(repository: repository, identity: identity)
    let id = try await skills.save(commandID: UUID(), name: "Brief", instructions: "Summarize {{subject}} for {{audience}}",
        parameters: [.init(name: "subject"), .init(name: "audience")], toolIDs: [])
    let original = try #require(try await repository.record(BlotV3.Skill.self, id: id, workspaceID: identity.workspaceID))
    _ = try await skills.save(commandID: UUID(), skillID: id, expectedVersion: 1, name: "Brief", instructions: "New instructions", parameters: [], toolIDs: [])
    #expect(try await skills.render(revisionID: original.activeRevisionId, values: ["subject": "{{audience}}", "audience": "staff"]) == "Summarize {{audience}} for staff")
    await #expect(throws: WorkspaceStorageError.invalidParameters) {
        _ = try await skills.render(revisionID: original.activeRevisionId, values: ["subject": "Topic"])
    }
}
