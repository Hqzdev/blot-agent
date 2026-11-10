import Foundation
import XCTest

@MainActor
final class PhoneTabNavigationTests: XCTestCase {
    func testReturningToEachSectionOpensItsRoot() {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        let destinations: [(WorkspaceRoute, WorkspaceRoute)] = [
            (.settings, .notifications), (.schedules, .createSchedule), (.overview, .files)
        ]
        for (tab, detail) in destinations {
            store.selectTab(tab)
            store.selectedRecordID = UUID()
            store.selectedAgentID = store.snapshot.agents.first?.metadata.id
            store.navigation.filesQuery = "previous search"
            store.navigate(detail)
            XCTAssertEqual(store.route, detail)
            XCTAssertFalse(store.history.isEmpty)

            store.selectTab(.chats)
            store.selectTab(tab)
            XCTAssertEqual(store.route, tab)
            XCTAssertEqual(store.rootRoute, tab)
            XCTAssertEqual(store.tab, tab)
            XCTAssertTrue(store.history.isEmpty)
            XCTAssertNil(store.selectedRecordID)
            XCTAssertNil(store.selectedAgentID)
            XCTAssertNil(store.selectedConversationID)
            XCTAssertTrue(store.navigation.filesQuery.isEmpty)
        }
    }

    func testTappingCurrentTabAlsoOpensItsRoot() {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        store.selectTab(.settings)
        store.navigate(.notifications)
        store.selectTab(.settings)
        XCTAssertEqual(store.route, .settings)
        XCTAssertTrue(store.history.isEmpty)
    }

    func testSwitchingSectionsKeepsTheConversationDraft() throws {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        let id = try XCTUnwrap(store.snapshot.conversations.first?.metadata.id)
        let count = store.snapshot.conversations.count
        store.openConversation(id)
        store.form.composer.draft = "Keep this unsent message"
        store.selectTab(.overview)
        XCTAssertNil(store.selectedConversationID)
        store.selectTab(.chats)
        XCTAssertEqual(store.route, .chats)
        XCTAssertEqual(store.snapshot.conversations.count, count)
        store.openConversation(id)
        XCTAssertEqual(store.form.composer.draft, "Keep this unsent message")
    }

    func testFilesReturnToTheirEntrySection() {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        for tab in [WorkspaceRoute.settings, .overview] {
            store.selectTab(tab)
            store.navigate(.files)
            store.navigate(.file)
            store.back()
            XCTAssertEqual(store.route, .files)
            store.back()
            XCTAssertEqual(store.route, tab)
            XCTAssertEqual(store.tab, tab)
        }
    }

    func testPreviewStartsAtTheNewTabRoots() {
        for route in [WorkspaceRoute.schedules, .overview] {
            let store = WorkspaceStore(mode: .preview, route: route)
            XCTAssertEqual(store.rootRoute, route)
            XCTAssertEqual(store.tab, route)
            XCTAssertTrue(store.history.isEmpty)
        }
    }
}
