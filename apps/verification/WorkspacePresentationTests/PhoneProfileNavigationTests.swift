import BlotDomain
import Foundation
import XCTest

@MainActor
final class PhoneProfileNavigationTests: XCTestCase {
    func testSettingsHaveOneProfileAndLegacyLinksOpenIt() {
        let store = WorkspaceStore(mode: .preview, route: .chats)
        let routes = PhoneSettingsCatalog.items.map(\.route)
        XCTAssertEqual(routes.filter { $0 == .settingsProfile }.count, 1)
        XCTAssertFalse(routes.contains(.account))
        XCTAssertFalse(routes.contains(.usage))
        for destination in [WorkspaceRoute.settingsProfile, .account, .usage] {
            store.selectTab(.chats)
            store.navigate(destination)
            XCTAssertEqual(store.route, .settingsProfile)
            XCTAssertEqual(store.history, [.settingsProfile])
        }
    }

    func testLegacyProfileDecodesWithoutContactEmail() throws {
        let data = Data(#"{"nickname":"Existing name","avatar":"AQID"}"#.utf8)
        let profile = try JSONDecoder().decode(WorkspaceUserProfile.self, from: data)
        XCTAssertEqual(profile.nickname, "Existing name")
        XCTAssertEqual(profile.avatar, Data([1, 2, 3]))
        XCTAssertNil(profile.contactEmail)
    }

    func testPasswordFailureKeepsSessionAndDeletionUsesItsOwnAction() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = try LocalWorkspaceService(databaseURL: folder.appendingPathComponent("workspace.sqlite"))
        let account = ProfileAccountSpy(local: local)
        let store = WorkspaceStore(mode: .live, service: account)
        await store.loadWorkspace()
        let ownerID = store.snapshot.ownerID
        store.navigate(.settingsProfile)
        let codeSent = await store.requestPasswordChangeCode()
        XCTAssertTrue(codeSent)
        XCTAssertEqual(account.codeRequests, 1)
        let invalid = await store.changeAccountPassword(code: "invalid", password: "password123")
        XCTAssertFalse(invalid)
        XCTAssertEqual(account.passwordChanges, 0)
        account.rejectPassword = true
        let rejected = await store.changeAccountPassword(code: "123456", password: "password123")
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.snapshot.ownerID, ownerID)
        XCTAssertEqual(account.signOuts, 0)
        store.deleteLocalAccount()
        await waitForSignOut(store)
        XCTAssertEqual(account.deletions, 1)
        XCTAssertEqual(account.signOuts, 0)
        XCTAssertEqual(store.route, .welcome)
        try await local.close()
        try FileManager.default.removeItem(at: folder)
    }

    func testSuccessfulPasswordChangeSignsOutWithoutDeletingData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = try LocalWorkspaceService(databaseURL: folder.appendingPathComponent("workspace.sqlite"))
        let account = ProfileAccountSpy(local: local)
        let store = WorkspaceStore(mode: .live, service: account)
        await store.loadWorkspace()
        let changed = await store.changeAccountPassword(code: "123456", password: "password123")
        XCTAssertTrue(changed)
        await waitForSignOut(store)
        XCTAssertEqual(account.passwordChanges, 1)
        XCTAssertEqual(account.signOuts, 1)
        XCTAssertEqual(account.deletions, 0)
        XCTAssertNil(store.snapshot.ownerID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("workspace.sqlite").path))
        try await local.close()
        try FileManager.default.removeItem(at: folder)
    }

    func testContactEmailPersistsWithoutChangingTheSignInAddress() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = try LocalWorkspaceService(databaseURL: folder.appendingPathComponent("workspace.sqlite"))
        let loaded = try await local.load()
        let ownerID = try XCTUnwrap(loaded?.ownerID)
        let account = ProfileAccountSpy(local: local)
        account.profile = .init(id: ownerID, email: "login@example.com", name: "Name", verified: true)
        let store = WorkspaceStore(mode: .live, service: account)
        await store.loadWorkspace()
        var profile = store.profile
        profile.contactEmail = "contact@example.com"
        let saved = await store.saveProfile(profile)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.form.account.email, "login@example.com")
        XCTAssertEqual(store.signInEmail, "login@example.com")
        let data = try await local.presentationState()
        let state = try JSONDecoder().decode(WorkspacePresentationState.self, from: XCTUnwrap(data))
        XCTAssertEqual(state.profile?.contactEmail, "contact@example.com")
        try await local.close()
        try FileManager.default.removeItem(at: folder)
    }

    private func waitForSignOut(_ store: WorkspaceStore) async {
        for _ in 0..<100 where store.busy { try? await _Concurrency.Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(store.busy)
    }
}

@MainActor
private final class ProfileAccountSpy: WorkspaceService, WorkspaceCommandProviding, WorkspaceAccountService, WorkspaceAccountPasswordChanging, WorkspaceLocalAccountDeleting {
    let local: LocalWorkspaceService
    var workspaceCommands: (any WorkspaceCommandService)? { local }
    var isAuthenticated = true
    var profile: WorkspaceAccountProfile?
    var codeRequests = 0
    var passwordChanges = 0
    var signOuts = 0
    var deletions = 0
    var rejectPassword = false
    init(local: LocalWorkspaceService) { self.local = local }
    func load() async throws -> WorkspaceSnapshot? { try await local.load() }
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot { try await local.execute(request, snapshot: snapshot) }
    func requestPasswordChangeCode() async throws { codeRequests += 1 }
    func changePassword(code: String, password: String) async throws {
        passwordChanges += 1
        if rejectPassword { throw WorkspaceServiceError.unavailable }
    }
    func signOut() async throws { signOuts += 1; isAuthenticated = false }
    func deleteLocalAccountData() async throws { deletions += 1; isAuthenticated = false }
}
