import BlotDomain
import BlotWorkspace
import SwiftUI
import UIKit
import XCTest

/// Runs the production SwiftUI list in a real UIKit window, with an isolated
/// preview store. Never opens or changes the signed-in user's workspace.
@MainActor
final class PhoneChatLifecycleTests: XCTestCase {
    func testPullToRefreshSynchronizesChatsAndPreservesDraftOnFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"))
        let service = RefreshablePhoneWorkspace(local: local)
        let store = WorkspaceStore(mode: .live, service: service)
        await store.loadWorkspace()
        store.selectTab(.chats)
        store.form.composer.draft = "Unsent message"
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: PhoneChatsView().environment(store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        await settle(window)
        let list = try XCTUnwrap(collections(in: window).first)
        let refresh = try XCTUnwrap(list.refreshControl, "The chat list must expose native pull-to-refresh")
        let previousCount = store.snapshot.conversations.count
        refresh.beginRefreshing()
        refresh.sendActions(for: .valueChanged)
        let deadline = Date().addingTimeInterval(5)
        while (service.refreshCount == 0 || refresh.isRefreshing) && Date() < deadline { await settle(window) }
        XCTAssertEqual(service.refreshCount, 1)
        XCTAssertEqual(store.snapshot.conversations.count, previousCount + 1)
        XCTAssertFalse(refresh.isRefreshing)
        XCTAssertEqual(store.form.composer.draft, "Unsent message")
        XCTAssertEqual(store.route, .chats)
        XCTAssertNil(store.error)

        let saved = store.snapshot
        service.failure = URLError(.notConnectedToInternet)
        await store.synchronizeAccount()
        XCTAssertEqual(store.snapshot, saved)
        XCTAssertEqual(store.form.composer.draft, "Unsent message")
        XCTAssertNotNil(store.error)
        window.isHidden = true; window.rootViewController = nil
        try await local.close()
        try FileManager.default.removeItem(at: directory)
    }

    func testRootProvidesStoreWithoutAnAncestorEnvironment() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        for route in [WorkspaceRoute.welcome, .chat] {
            let store = WorkspaceStore(mode: .preview, route: route)
            let host = UIHostingController(rootView: WorkspaceRootView(store: store))
            window.rootViewController = host
            window.makeKeyAndVisible()
            await settle(window)
            XCTAssertFalse(host.view.bounds.isEmpty)
        }
    }

    func testEachAgentKeepsOneChatAcrossRepeatedOpenAndPickerChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"))
        let store = WorkspaceStore(mode: .live, service: service)
        await store.loadWorkspace()
        var agents: [UUID] = []
        for name in ["First agent", "Second agent"] {
            store.form.agent = WorkspaceAgentForm(name: name, instructions: "Help")
            await store.perform(.createAgent)
            agents.append(try XCTUnwrap(store.selectedAgentID))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: WorkspaceRootView(store: store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        var chats: [UUID: UUID] = [:]
        for _ in 0..<5 {
            for agent in agents {
                await store.startNewChat(with: agent)
                await settle(window)
                let id = try XCTUnwrap(store.selectedConversationID)
                if let existing = chats[agent] { XCTAssertEqual(existing, id) }
                chats[agent] = id
                XCTAssertEqual(store.currentConversation?.agentId, agent)
                XCTAssertNil(store.error)
            }
        }
        await store.chooseChatAgent(agents[0])
        XCTAssertEqual(store.selectedConversationID, chats[agents[0]])
        XCTAssertEqual(store.snapshot.conversations.count, 2)
        store.selectTab(.chats)
        store.restoreNavigation([])
        await settle(window)
        let deadline = Date().addingTimeInterval(2)
        while collections(in: window).isEmpty && Date() < deadline { await settle(window) }
        XCTAssertEqual(store.route, .chats)
        await assertRowCount(2, in: window)
        window.isHidden = true; window.rootViewController = nil
        try await service.close()
        try FileManager.default.removeItem(at: directory)
    }

    func testThinkingDotsActuallyAnimate() async throws {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: WorkspaceReplyBubble(draft: .init(messageID: UUID()))
            .environment(store).environment(\.scenePhase, .active)
            .frame(width: 120, height: 70))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        await settle(window)
        func capture() -> Data? {
            UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }.pngData()
        }
        let first = try XCTUnwrap(capture())
        try await _Concurrency.Task.sleep(for: .milliseconds(220))
        let second = try XCTUnwrap(capture())
        XCTAssertNotEqual(first, second, "Thinking dots must change size and brightness over time")
    }

    func testReplyStaysBehindThinkingIndicatorUntilFinished() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let channel = AsyncThrowingStream<ChatModelEvent, Error>.makeStream()
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"),
            makeModel: { _ in ControlledPhoneReply(events: channel.stream) })
        let store = WorkspaceStore(mode: .live, service: service)
        await store.loadWorkspace()
        await store.perform(.createConversation, next: .chat)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: WorkspaceRootView(store: store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        store.form.composer.draft = "Synthetic reply presentation check"
        await store.perform(.send)
        channel.continuation.yield(.text("A complete "))
        await settle(window)
        XCTAssertNotNil(store.currentReplyDraft)
        XCTAssertTrue(store.isReplying)
        XCTAssertEqual(PhoneMessageTimeline.rows(in: store.currentMessages).filter { $0.message.role == .assistant }.count, 0)
        attach(window, name: "Waiting for a whole reply")
        channel.continuation.yield(.text("reply.\n\nWith a second paragraph."))
        channel.continuation.yield(.finished(.stop))
        channel.continuation.finish()
        let deadline = Date().addingTimeInterval(5)
        while store.isReplying && Date() < deadline { await settle(window) }
        await settle(window)
        XCTAssertFalse(store.isReplying)
        XCTAssertNil(store.currentReplyDraft)
        let replies = PhoneMessageTimeline.rows(in: store.currentMessages).filter { $0.message.role == .assistant }
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies.first?.message.content, "A complete reply.\n\nWith a second paragraph.")
        XCTAssertEqual(replies.first?.message.delivery, .completed)
        XCTAssertNil(store.error)
        attach(window, name: "Whole reply received")
        window.isHidden = true; window.rootViewController = nil
        try await service.close()
        try FileManager.default.removeItem(at: directory)
    }

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
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
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
        try await _Concurrency.Task.sleep(for: .milliseconds(300))
        window.isHidden = true; window.rootViewController = nil
        try await service.close()
        try FileManager.default.removeItem(at: directory)
    }

    func testPinnedChatsOnlyAppearInTheTopStripAndReturnWhenUnpinned() async throws {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        let ids = store.snapshot.conversations.map(\.metadata.id)
        XCTAssertGreaterThan(ids.count, 1)
        for id in ids { store.setChatArchived(id, archived: false) }
        store.error = nil; store.notice = nil
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: PhoneChatsView().environment(store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        await assertRowCount(ids.count, in: window)
        for (index, id) in ids.enumerated() {
            store.toggleChatPin(id)
            await settle(window)
            // One shared strip plus only the remaining unpinned chats.
            await assertRowCount(1 + ids.count - index - 1, in: window)
        }
        XCTAssertEqual(store.pinnedConversations.count, ids.count)
        attach(window, name: "Pinned chats only in the top strip")
        for (index, id) in ids.enumerated() {
            store.toggleChatPin(id)
            await settle(window)
            let stripCount = index == ids.count - 1 ? 0 : 1
            await assertRowCount(stripCount + index + 1, in: window)
        }
        XCTAssertTrue(store.pinnedConversations.isEmpty)
        XCTAssertEqual(store.snapshot.conversations.count, ids.count)
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
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }

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
        await assertRowCount(1, in: window)

        store.error = "Test error"; store.notice = "Test notice"
        await settle(window)
        await assertRowCount(2, in: window) // empty state + one feedback row
        store.error = nil; store.notice = nil
        await settle(window)
        await assertRowCount(1, in: window)

        store.back()
        await settle(window)
        await assertRowCount(1, in: window)
        for _ in 0..<8 {
            store.selectTab(.agents)
            await settle(window)
            await assertRowCount(store.snapshot.agents.count, in: window)
            store.selectTab(.chats)
            await settle(window)
            await assertRowCount(1, in: window)
        }
    }

    private func settle(_ window: UIWindow) async {
        window.layoutIfNeeded()
        try? await _Concurrency.Task.sleep(for: .milliseconds(120))
        window.layoutIfNeeded()
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertRowCount(_ expected: Int, in window: UIWindow, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        var counts: [Int] = []
        repeat {
            window.layoutIfNeeded()
            counts = collections(in: window).filter { !$0.isHidden && $0.window != nil }.map { list in
                (0..<list.numberOfSections).reduce(0) { $0 + list.numberOfItems(inSection: $1) }
            }
            if counts.contains(expected) { return }
            await settle(window)
        } while Date() < deadline
        XCTFail("Expected \(expected) rows, mounted lists: \(counts)", file: file, line: line)
    }

    private func collections(in view: UIView) -> [UICollectionView] {
        (view as? UICollectionView).map { [$0] } ?? view.subviews.flatMap { collections(in: $0) }
    }
}

private struct ControlledPhoneReply: ChatModel {
    let events: AsyncThrowingStream<ChatModelEvent, Error>
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> { events }
}

@MainActor
private final class RefreshablePhoneWorkspace: WorkspaceService, WorkspaceCommandProviding, WorkspaceAccountSynchronizing {
    private let local: LocalWorkspaceService
    var workspaceCommands: (any WorkspaceCommandService)? { local }
    private(set) var refreshCount = 0
    var failure: (any Error)?

    init(local: LocalWorkspaceService) { self.local = local }
    func load() async throws -> WorkspaceSnapshot? { try await local.load() }
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        try await local.execute(request, snapshot: snapshot)
    }
    func synchronizeAccount() async throws {
        refreshCount += 1
        if let failure { throw failure }
        let request = WorkspaceRequest(action: .createConversation, form: WorkspaceForm(),
            selectedAgentID: nil, selectedConversationID: nil, selectedRecordID: nil)
        _ = try await local.execute(request, snapshot: local.currentSnapshot())
    }
}
