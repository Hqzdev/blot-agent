import BlotWorkspace
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PhoneFirstAgentTests: XCTestCase {
    func testEmptyAccountRequiresFirstBlotAndReturningAccountOpensChats() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"))
        let store = WorkspaceStore(mode: .live, service: local)
        await store.loadWorkspace()
        XCTAssertEqual(store.rootRoute, .firstAgent)
        XCTAssertEqual(store.route, .firstAgent)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(PhoneTabBar.isVisible(on: store.route))
        store.navigate(.settings)
        store.selectTab(.chats)
        XCTAssertEqual(store.route, .firstAgent)

        let setup = completedDraft()
        await setup.finish(using: store)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.snapshot.agents.count, 1)
        XCTAssertEqual(store.snapshot.agents.first?.name, "Искра")
        XCTAssertEqual(store.snapshot.agents.first?.avatarShape, "hexagon")
        XCTAssertEqual(store.snapshot.agents.first?.avatarColor, "purple")
        XCTAssertEqual(store.route, .chat)
        XCTAssertEqual(store.rootRoute, .chats)
        XCTAssertEqual(store.currentConversation?.agentId, store.snapshot.agents.first?.metadata.id)
        let returning = WorkspaceStore(mode: .live, service: local)
        await returning.loadWorkspace()
        XCTAssertEqual(returning.route, .chats)
        XCTAssertEqual(returning.snapshot.agents.count, 1)
        try await local.close()
        try FileManager.default.removeItem(at: directory)
    }

    func testSkippingRoleCreatesGeneralAssistantWithoutChangingIdentity() async throws {
        let store = WorkspaceStore(mode: .preview, route: .firstAgent)
        let setup = PhoneFirstAgentSetup()
        setup.skipRole(instructions: "Help with everyday tasks")
        XCTAssertEqual(setup.step, .introduction, "Only the role step can be skipped")
        setup.advance()
        setup.draft.name = "Искра"
        setup.advance()
        setup.draft.shape = "drop"
        setup.draft.color = "blue"
        setup.advance()
        setup.skipRole(instructions: "Help with everyday tasks")
        XCTAssertEqual(setup.step, .preparing)
        await setup.finish(using: store)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.snapshot.agents.last?.name, "Искра")
        XCTAssertEqual(store.snapshot.agents.last?.avatarShape, "drop")
        XCTAssertEqual(store.snapshot.agents.last?.avatarColor, "blue")
        XCTAssertEqual(store.snapshot.agents.last?.instructions, "Help with everyday tasks")
        XCTAssertEqual(store.route, .chat)
    }

    func testTemplatesAndBackPreserveIdentityAndRequireCustomInstructions() {
        let setup = PhoneFirstAgentSetup()
        setup.advance()
        setup.draft.name = "  Искра  "
        setup.advance()
        setup.draft.shape = "hexagon"
        setup.draft.color = "purple"
        setup.advance()
        for role in PhoneFirstAgentSetup.Role.allCases {
            setup.select(role, instructions: role.instructions)
            XCTAssertEqual(setup.draft.name, "Искра")
            XCTAssertEqual(setup.draft.shape, "hexagon")
            XCTAssertEqual(setup.draft.color, "purple")
        }
        XCTAssertFalse(setup.canContinue)
        setup.draft.instructions = "Help me learn Swift"
        XCTAssertTrue(setup.canContinue)
        setup.back()
        setup.back()
        XCTAssertEqual(setup.step, .name)
        XCTAssertEqual(setup.draft.name, "Искра")
        XCTAssertEqual(setup.draft.instructions, "Help me learn Swift")
        setup.draft.name = " \n "
        XCTAssertFalse(setup.canContinue)
    }

    func testRetryAfterChatFailureReusesSavedBlotAndAcceptsEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"))
        let service = FailingFirstAgentService(local: local)
        let store = WorkspaceStore(mode: .live, service: service)
        await store.loadWorkspace()
        let setup = completedDraft()
        service.failure = .createAgent
        await setup.finish(using: store)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.snapshot.agents.isEmpty)
        XCTAssertEqual(store.route, .firstAgent)
        service.failure = .createConversation
        await setup.finish(using: store)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.snapshot.agents.count, 1)
        let id = store.snapshot.agents.first?.metadata.id
        XCTAssertEqual(store.route, .firstAgent)
        setup.back()
        setup.select(.design, instructions: "Help with design")
        setup.advance()
        service.failure = nil
        await setup.finish(using: store)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.snapshot.agents.count, 1)
        XCTAssertEqual(store.snapshot.agents.first?.metadata.id, id)
        XCTAssertEqual(store.snapshot.agents.first?.instructions, "Help with design")
        XCTAssertEqual(store.snapshot.conversations.count, 1)
        XCTAssertEqual(store.route, .chat)
        try await local.close()
        try FileManager.default.removeItem(at: directory)
    }

    func testFirstBlotScreensRenderOnPhysicalPhone() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let store = WorkspaceStore(mode: .preview, route: .firstAgent)
        store.language = "ru"
        let setup = PhoneFirstAgentSetup()
        window.rootViewController = UIHostingController(rootView: PhoneFirstAgentView(setup: setup, resourceBundle: Bundle(for: Self.self)).environment(store))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for step in [PhoneFirstAgentSetup.Step.introduction, .name, .appearance, .role] {
            await settle(window)
            XCTAssertEqual(setup.step, step)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "First blot - \(step)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if step == .name { setup.draft.name = "Искра" }
            setup.advance()
        }
    }

    private func completedDraft() -> PhoneFirstAgentSetup {
        let setup = PhoneFirstAgentSetup()
        setup.advance()
        setup.draft.name = "Искра"
        setup.advance()
        setup.draft.shape = "hexagon"
        setup.draft.color = "purple"
        setup.advance()
        setup.select(.assistant, instructions: PhoneFirstAgentSetup.Role.assistant.instructions)
        setup.advance()
        return setup
    }

    private func settle(_ window: UIWindow) async {
        window.layoutIfNeeded()
        try? await _Concurrency.Task.sleep(for: .milliseconds(400))
    }
}

@MainActor
private final class FailingFirstAgentService: WorkspaceService, WorkspaceCommandProviding {
    private let local: LocalWorkspaceService
    var failure: WorkspaceAction?
    var workspaceCommands: (any WorkspaceCommandService)? { local }
    init(local: LocalWorkspaceService) { self.local = local }
    func load() async throws -> WorkspaceSnapshot? { try await local.load() }
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        if request.action == failure { throw URLError(.notConnectedToInternet) }
        return try await local.execute(request, snapshot: snapshot)
    }
}
