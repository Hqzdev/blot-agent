import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct GroupEditingFixture {
    let directory: URL
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let agents: [UUID]
    let groupID: UUID

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
        identity = try await repository.localIdentity()
        let service = WorkspaceAgentService(repository: repository, identity: identity)
        var ids: [UUID] = []
        for name in ["First", "Second", "Third"] {
            ids.append(try await service.save(commandID: UUID(), draft: .init(name: name, instructions: "Help")))
        }
        agents = ids
        groupID = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "Team", agentIDs: Array(ids.prefix(2)))
    }
}

@Test func editingGroupSavesMembersCoordinatorAndTitleTogetherAndKeepsHistory() async throws {
    let fixture = try await GroupEditingFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let service = WorkspaceGroupService(repository: fixture.repository, identity: fixture.identity)
    let messageID = try await WorkspaceChatService(repository: fixture.repository, identity: fixture.identity)
        .sendMessage(commandID: UUID(), conversationID: fixture.groupID, content: "Original conversation")
    let command = UUID()
    let ids = [fixture.agents[2], fixture.agents[0]]
    for _ in 0..<2 {
        try await service.update(commandID: command, conversationID: fixture.groupID, expectedVersion: 1,
            title: "  Launch team  ", agentIDs: ids)
    }
    let saved = try await fixture.repository.projection(identity: fixture.identity)
    let group = try #require(saved.conversations.first { $0.metadata.id == fixture.groupID })
    #expect(group.title == "Launch team" && group.agentId == fixture.agents[2] && group.metadata.version == 2)
    #expect(Set(saved.participants.filter { $0.kind == .agent && !$0.removed }.map(\.participantId)) == Set(ids))
    #expect(saved.participants.contains { $0.participantId == fixture.agents[1] && $0.removed })
    #expect(saved.participants.contains { $0.participantId == fixture.identity.ownerID && !$0.removed })
    #expect(saved.agents.count == 3 && saved.messages.map(\.metadata.id) == [messageID])
    try await fixture.repository.close()
    let reopened = try await workspaceTestRepository(url: fixture.directory.appendingPathComponent("db.sqlite"))
    #expect(try await reopened.projection(identity: fixture.identity).conversations.first?.agentId == fixture.agents[2])
}

@Test func invalidOrStaleGroupEditsLeaveTheEntireGroupUntouched() async throws {
    let fixture = try await GroupEditingFixture()
    defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let service = WorkspaceGroupService(repository: fixture.repository, identity: fixture.identity)
    let before = try await fixture.repository.projection(identity: fixture.identity)
    for ids in [[UUID()], [], [fixture.agents[0], fixture.agents[0]]] {
        await #expect(throws: (any Error).self) {
            try await service.update(commandID: UUID(), conversationID: fixture.groupID, expectedVersion: 1, title: "Changed", agentIDs: ids)
        }
        #expect(try await fixture.repository.projection(identity: fixture.identity) == before)
    }
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        try await service.update(commandID: UUID(), conversationID: fixture.groupID, expectedVersion: 100,
            title: "Changed", agentIDs: [fixture.agents[0]])
    }
    #expect(try await fixture.repository.projection(identity: fixture.identity) == before)
}
