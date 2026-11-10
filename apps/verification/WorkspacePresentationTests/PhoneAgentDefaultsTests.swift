import Foundation
import XCTest

@MainActor
final class PhoneAgentDefaultsTests: XCTestCase {
    func testAgentSavesBuiltInToolsAndKeepsConnectedAppTools() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"))
        let store = WorkspaceStore(mode: .live, service: service)
        await store.loadWorkspace()
        store.beginAgentCreation()
        store.form.agent.name = "Researcher"
        store.form.agent.instructions = "Prepare reports"
        store.form.agent.toolIDs = ["apple_calendar_read"]
        await store.perform(.createAgent)
        XCTAssertNil(store.error)
        let agentID = try XCTUnwrap(store.selectedAgentID)
        let revision = try XCTUnwrap(store.snapshot.configurations?.first { $0.agentId == agentID })
        XCTAssertEqual(Set(revision.toolIds), ["file_read", "document_create", "memory_candidate", "apple_calendar_read"])
        store.selectAgent(agentID, destination: .editAgent)
        store.form.agent.name = "Updated researcher"
        await store.perform(.saveAgent)
        XCTAssertNil(store.error)
        let updated = try XCTUnwrap(store.snapshot.configurations?.filter { $0.agentId == agentID }.max { $0.revision < $1.revision })
        XCTAssertEqual(Set(updated.toolIds), Set(revision.toolIds))
        try await service.close()
        try FileManager.default.removeItem(at: directory)
    }
}
