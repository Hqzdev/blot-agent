import BlotDomain
import Foundation
import XCTest

final class PhoneConversationIdentityTests: XCTestCase {
    func testRenamedGroupUsesActiveParticipantsRatherThanCoordinatorOrTitle() throws {
        let coordinator = try agent("CEO")
        let writer = try agent("Writer")
        let unrelated = try agent("Launch team")
        let group = try conversation(title: "Launch team", coordinator: coordinator, group: true)
        let identity = PhoneConversationIdentity(conversation: group, agents: [coordinator, writer, unrelated], participants: [
            try participant(coordinator.metadata.id, in: group), try participant(writer.metadata.id, in: group)
        ])
        XCTAssertTrue(identity.isGroup)
        XCTAssertEqual(identity.title, "Launch team")
        XCTAssertEqual(identity.members.map(\.name), ["CEO", "Writer"])
    }

    func testRemovedHumanAndOtherConversationParticipantsAreExcluded() throws {
        let agents = try [agent("CEO"), agent("Writer"), agent("Reviewer"), agent("Other group")]
        let group = try conversation(title: "Group", coordinator: agents[0], group: true)
        let other = try conversation(title: "Other", coordinator: agents[3], group: true)
        let identity = PhoneConversationIdentity(conversation: group, agents: agents, participants: [
            try participant(agents[0].metadata.id, in: group),
            try participant(agents[0].metadata.id, in: group),
            try participant(agents[1].metadata.id, in: group, removed: true),
            try participant(agents[2].metadata.id, in: group, kind: .user),
            try participant(agents[3].metadata.id, in: other),
            try participant(UUID(), in: group)
        ])
        XCTAssertEqual(identity.members.map(\.metadata.id), [agents[0].metadata.id])
    }

    func testGroupRepliesKeepTheirActualAuthorIncludingFormerMembers() throws {
        let agents = try [agent("CEO"), agent("Writer")]
        let group = try conversation(title: "Group", coordinator: agents[0], group: true)
        let identity = PhoneConversationIdentity(conversation: group, agents: agents, participants: [
            try participant(agents[0].metadata.id, in: group), try participant(agents[1].metadata.id, in: group, removed: true)
        ])
        XCTAssertEqual(identity.author(of: try message(in: group, author: agents[1].metadata.id))?.name, "Writer")
        XCTAssertNil(identity.author(of: try message(in: group)))
        XCTAssertNil(identity.author(of: try message(in: group, author: UUID())))
        XCTAssertNil(identity.author(of: try message(in: group, author: agents[0].metadata.id, role: .user)))
    }

    func testDirectChatKeepsItsAgentAndLegacyReplyAttribution() throws {
        let ceo = try agent("CEO")
        let chat = try conversation(title: "Renamed direct chat", coordinator: ceo, group: false)
        let identity = PhoneConversationIdentity(conversation: chat, agents: [ceo], participants: [])
        XCTAssertFalse(identity.isGroup)
        XCTAssertEqual(identity.title, "CEO")
        XCTAssertTrue(identity.members.isEmpty)
        XCTAssertEqual(identity.author(of: try message(in: chat))?.metadata.id, ceo.metadata.id)
    }

    func testMissingMembershipDoesNotInventGroupMembersFromTheCoordinator() throws {
        let ceo = try agent("CEO")
        let group = try conversation(title: "Group", coordinator: ceo, group: true)
        let identity = PhoneConversationIdentity(conversation: group, agents: [ceo], participants: [])
        XCTAssertTrue(identity.isGroup)
        XCTAssertTrue(identity.members.isEmpty)
        XCTAssertEqual(identity.title, "Group")
    }

    private func metadata() throws -> BlotV3.RecordMetadata {
        try .init(id: UUID(), ownerId: UUID(), version: 1, createdAt: Date(), updatedAt: Date())
    }
    private func agent(_ name: String) throws -> BlotV3.AgentProfile {
        try .init(metadata: metadata(), name: name, roleId: "assistant", avatarShape: "cloud", avatarColor: "purple",
                  instructions: "Help", modelId: "gigachat", accessMode: .ask_first)
    }
    private func conversation(title: String, coordinator: BlotV3.AgentProfile, group: Bool) throws -> BlotV3.Conversation {
        try .init(metadata: metadata(), agentId: coordinator.metadata.id, title: title, mobileOwned: true, pinned: false,
                  archived: false, kind: group ? .group : .direct)
    }
    private func participant(_ id: UUID, in chat: BlotV3.Conversation, removed: Bool = false,
                             kind: BlotV3.ParticipantKind = .agent) throws -> BlotV3.ConversationParticipant {
        try .init(metadata: metadata(), conversationId: chat.metadata.id, participantId: id, kind: kind, removed: removed)
    }
    private func message(in chat: BlotV3.Conversation, author: UUID? = nil,
                         role: BlotV3.MessageRole = .assistant) throws -> BlotV3.Message {
        try .init(metadata: metadata(), conversationId: chat.metadata.id, role: role, content: "Reply", delivery: .completed,
                  commandId: UUID(), artifactIds: [], authorAgentId: author)
    }
}
