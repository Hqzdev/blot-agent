import SwiftUI
import UIKit
import XCTest

/// Runs the production SwiftUI list in a real UIKit window, with an isolated
/// preview store. Never opens or changes the signed-in user's workspace.
@MainActor
final class PhoneChatLifecycleTests: XCTestCase {
    func testRapidTabChangesAndDraftEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"))
        let store = WorkspaceStore(mode: .live, service: service)
        await store.loadWorkspace()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: WorkspaceRootView(store: store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        await settle(window)

        for cycle in 0..<5 {
            for tab in [WorkspaceRoute.chats, .agents, .files, .settings] {
                for index in 0..<40 { store.form.composer.draft = "Draft \(cycle)-\(index)" }
                store.selectTab(tab)
                await settle(window)
                XCTAssertEqual(store.tab, tab)
                XCTAssertEqual(store.rootRoute, tab)
                XCTAssertFalse(store.busy)
            }
        }
        store.persistChatState(immediately: true)
        try await Task.sleep(for: .milliseconds(300))
        try await service.close()
        try FileManager.default.removeItem(at: directory)
    }

    func testDeletePinnedAndLastChatsThenSwitchTabs() async throws {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        // Presentation fixtures may contain only archived pins. Explicitly seed
        // active pinned chats so the disappearing pinned-strip row is exercised.
        for chat in store.snapshot.conversations.prefix(2) {
            store.setChatArchived(chat.metadata.id, archived: false)
            store.toggleChatPin(chat.metadata.id)
        }
        store.error = nil; store.notice = nil
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: WorkspaceRootView(store: store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }

        await settle(window)
        XCTAssertFalse(collections(in: window).isEmpty, "The production List must be mounted")
        let pinned = store.pinnedConversations.map(\.metadata.id)
        XCTAssertFalse(pinned.isEmpty)
        for id in pinned {
            store.deleteChat(id)
            await settle(window)
            XCTAssertNil(store.snapshot.conversations.first { $0.metadata.id == id })
        }

        // Archive row removal and empty-state insertion share the same update.
        for chat in store.snapshot.conversations {
            store.setChatArchived(chat.metadata.id, archived: true)
            await settle(window)
        }
        store.navigate(.archivedChats)
        await settle(window)
        for chat in store.snapshot.conversations {
            store.deleteChat(chat.metadata.id)
            await settle(window)
        }
        XCTAssertTrue(store.snapshot.conversations.isEmpty)
        assertRowCount(1, in: window)

        store.error = "Test error"; store.notice = "Test notice"
        await settle(window)
        assertRowCount(2, in: window) // empty state + one feedback row
        store.error = nil; store.notice = nil
        await settle(window)
        assertRowCount(1, in: window)

        store.back()
        await settle(window)
        assertRowCount(1, in: window)
        for _ in 0..<8 {
            store.selectTab(.agents)
            await settle(window)
            assertRowCount(store.snapshot.agents.count, in: window)
            store.selectTab(.chats)
            await settle(window)
            assertRowCount(1, in: window)
        }
    }

    private func settle(_ window: UIWindow) async {
        window.layoutIfNeeded()
        try? await _Concurrency.Task.sleep(for: .milliseconds(120))
        window.layoutIfNeeded()
    }

    private func assertRowCount(_ expected: Int, in window: UIWindow, file: StaticString = #filePath, line: UInt = #line) {
        let lists = collections(in: window).filter { !$0.isHidden && $0.window != nil }
        XCTAssertTrue(lists.contains { list in
            (0..<list.numberOfSections).reduce(0) { $0 + list.numberOfItems(inSection: $1) } == expected
        }, "Expected a mounted list with \(expected) rows", file: file, line: line)
    }

    private func collections(in view: UIView) -> [UICollectionView] {
        (view as? UICollectionView).map { [$0] } ?? view.subviews.flatMap { collections(in: $0) }
    }
}
