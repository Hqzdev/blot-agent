import BlotDomain
import Foundation
import XCTest

final class PhoneSearchResultsTests: XCTestCase {
    func testEmptyQueryShowsEveryAgentAndGroupIncludingTheArchive() throws {
        let fixture = try Fixture()
        let result = PhoneSearchResults(snapshot: fixture.snapshot, query: "  \n ")
        XCTAssertEqual(Set(result.agents.map(\.metadata.id)), Set(fixture.snapshot.agents.map(\.metadata.id)))
        XCTAssertEqual(Set(result.groups.map(\.metadata.id)), [fixture.group.metadata.id, fixture.archived.metadata.id])
        XCTAssertFalse(result.isEmpty)
    }
    func testQueryMatchesNamesInstructionsAndGroupTitlesWithoutCaseSensitivity() throws {
        let fixture = try Fixture()
        XCTAssertEqual(PhoneSearchResults(snapshot: fixture.snapshot, query: " writer ").agents.map(\.name), ["Writer"])
        XCTAssertEqual(PhoneSearchResults(snapshot: fixture.snapshot, query: "EDITORIAL").agents.map(\.name), ["Writer"])
        XCTAssertEqual(PhoneSearchResults(snapshot: fixture.snapshot, query: " launch ").groups.map(\.title), ["Launch team"])
    }
    func testGroupMatchesItsActiveMembersButNotRemovedOrOtherParticipants() throws {
        let fixture = try Fixture()
        let result = PhoneSearchResults(snapshot: fixture.snapshot, query: "writer")
        XCTAssertEqual(result.groups.map(\.metadata.id), [fixture.group.metadata.id])
        XCTAssertTrue(PhoneSearchResults(snapshot: fixture.snapshot, query: "Reviewer").groups.isEmpty)
    }
    func testDirectConversationsAndMessageTextDoNotBecomeGroupResults() throws {
        let fixture = try Fixture()
        XCTAssertTrue(PhoneSearchResults(snapshot: fixture.snapshot, query: "Private notes").isEmpty)
        XCTAssertTrue(PhoneSearchResults(snapshot: fixture.snapshot, query: "No such agent").isEmpty)
    }

    private struct Fixture {
        let snapshot: WorkspaceSnapshot
        let group: BlotV3.Conversation
        let archived: BlotV3.Conversation
        init() throws {
            func metadata() throws -> BlotV3.RecordMetadata {
                try .init(id: UUID(), ownerId: UUID(), version: 1, createdAt: Date(), updatedAt: Date())
            }
            func agent(_ name: String, instructions: String = "Help") throws -> BlotV3.AgentProfile {
                try .init(metadata: metadata(), name: name, roleId: "assistant", avatarShape: "cloud", avatarColor: "purple",
                          instructions: instructions, modelId: "gigachat", accessMode: .ask_first)
            }
            let agents = try [agent("CEO"), agent("Writer", instructions: "Editorial work"), agent("Reviewer")]
            func conversation(_ title: String, group: Bool = true, archived: Bool = false) throws -> BlotV3.Conversation {
                try .init(metadata: metadata(), agentId: agents[0].metadata.id, title: title, mobileOwned: true,
                          pinned: false, archived: archived, kind: group ? .group : .direct)
            }
            group = try conversation("Launch team")
            archived = try conversation("Old group", archived: true)
            var data = WorkspaceSnapshot()
            data.agents = agents
            data.conversations = [group, archived, try conversation("Private notes", group: false)]
            data.messages = try [.init(metadata: metadata(), conversationId: group.metadata.id, role: .user,
                                      content: "Private notes", delivery: .saved, commandId: UUID(), artifactIds: [])]
            data.participants = try [
                .init(metadata: metadata(), conversationId: group.metadata.id, participantId: agents[1].metadata.id, kind: .agent, removed: false),
                .init(metadata: metadata(), conversationId: archived.metadata.id, participantId: agents[1].metadata.id, kind: .agent, removed: true),
                .init(metadata: metadata(), conversationId: UUID(), participantId: agents[2].metadata.id, kind: .agent, removed: false)
            ]
            snapshot = data
        }
    }
}
