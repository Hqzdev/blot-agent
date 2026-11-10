import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor BrowserCredentials: WorkspaceCredentialStore {
    var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}
private actor InaccessibleBrowserCredentials: WorkspaceCredentialStore {
    func read(_ name: String) throws -> Data? { throw WorkspaceStorageError.permissionDenied }
    func write(_ value: Data, name: String) throws { throw WorkspaceStorageError.permissionDenied }
    func remove(_ name: String) throws { throw WorkspaceStorageError.permissionDenied }
}
private actor BrowserDriver: WorkspaceBrowserExecuting {
    private var document = UUID()
    private(set) var executions = 0
    private(set) var stopped = false
    var uncertain = false
    func changePage() { document = UUID() }
    func setUncertain() { uncertain = true }
    func resetStopped() { stopped = false }
    func prepare(_ command: WorkspaceBrowserCommand) -> WorkspaceBrowserBinding {
        .init(tabID: command.id, documentID: document, url: "https://example.com/form", target: "Submit form")
    }
    func execute(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) throws -> WorkspaceBrowserResult {
        executions += 1
        if uncertain { throw WorkspaceBrowserError.unknown }
        return .value(.object(["state": .string("completed")]))
    }
    func stop(scope: WorkspaceBrowserScope?) { stopped = true }
}
private struct BrowserFixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let driver = BrowserDriver()
    let service: WorkspaceBrowserService
    let files: WorkspaceFileService
    let agent: UUID
    let chat: UUID
    let source: UUID
    init(request: String = "Use the approved website") async throws {
        repository = try await workspaceTestRepository(url: folder.appendingPathComponent("workspace.sqlite"))
        identity = try await repository.localIdentity()
        files = WorkspaceFileService(repository: repository, identity: identity, directory: folder.appendingPathComponent("Attachments"))
        service = WorkspaceBrowserService(repository: repository, identity: identity, credentials: BrowserCredentials(), driver: driver)
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Researcher", instructions: "Use approved tools"))
        chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Web", agentID: agent)
        source = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: request)
        try await service.configure(agents: [agent], origins: ["https://example.com/path"])
    }
    var context: WorkspaceToolContext { .init(sourceMessageID: source, taskID: nil, allowedToolIDs: Set(WorkspaceBrowserCatalog.toolIDs), agentID: agent) }
    func tools(_ confirm: @escaping @Sendable (String, String) async throws -> Bool = { _, _ in true }) -> WorkspaceBrowserTools {
        .init(service: service, repository: repository, identity: identity, files: files, confirm: confirm)
    }
    func call(_ id: String) -> ChatToolCall { .init(id: id, name: "browser_click", arguments: .object(["tab_id": .string(UUID().uuidString), "document_id": .string(UUID().uuidString), "element_id": .string("1:0")])) }
}

@Test func browserURLPolicyRejectsExternalAppsCredentialsAndUnscopedOrigins() throws {
    for value in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,hi", "mailto:someone@example.com", "https://user:secret@example.com", "http://example.com", "https://"] {
        #expect(throws: WorkspaceBrowserError.self) { _ = try WorkspaceBrowserURL.validated(value) }
    }
    #expect(try WorkspaceBrowserURL.origin(WorkspaceBrowserURL.validated("https://EXAMPLE.com:443/path?q=1#s")) == "https://example.com")
    #expect(try WorkspaceBrowserURL.validated("http://127.0.0.1:8080/test").port == 8080)
    #expect(WorkspaceBrowserURL.restorable(URL(string: "https://example.com/callback?code=secret#token")!)?.absoluteString == "https://example.com/callback")
}

@Test func browserActionsRequireApprovalRejectChangedPageAndReplayDurably() async throws {
    let f = try await BrowserFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let denied = try await f.tools { _, _ in false }.execute(f.call("deny"), context: f.context)
    #expect(denied.mcpFields["state"] == .string("failed")); #expect(await f.driver.executions == 0)
    let stale = try await f.tools { _, _ in await f.driver.changePage(); return true }.execute(f.call("stale"), context: f.context)
    #expect(stale.mcpFields["state"] == .string("failed")); #expect(await f.driver.executions == 0)
    let call = f.call("once"), tools = f.tools()
    let value = try await tools.execute(call, context: f.context)
    #expect(value.mcpFields["state"] == .string("completed"))
    #expect(try await tools.execute(call, context: f.context) == value); #expect(await f.driver.executions == 1)
    let projection = try await f.repository.projection(identity: f.identity)
    #expect(projection.invocations.filter { $0.state == .succeeded }.count == 1)
    await f.service.suspend()
}

@Test func browserGrantsAreDeviceLocalAndRevocationWinsDuringConfirmation() async throws {
    let f = try await BrowserFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let other = WorkspaceBrowserService(repository: f.repository, identity: f.identity, credentials: BrowserCredentials(), driver: f.driver)
    await #expect(throws: WorkspaceBrowserError.denied) { _ = try await other.authorize("browser_snapshot", context: f.context) }
    let result = try await f.tools { _, _ in try await f.service.configure(agents: [], origins: []); return true }.execute(f.call("revoke"), context: f.context)
    #expect(result.mcpFields["state"] == .string("failed")); #expect(await f.driver.executions == 0)
    #expect(try await f.tools().availableDefinitions(context: f.context).isEmpty)
    await f.service.suspend()
}

@Test func browserUnknownOutcomeBlocksWritesUntilOwnerVerificationAndReadOnlyNarrowsGrant() async throws {
    let f = try await BrowserFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    await f.driver.setUncertain()
    let result = try await f.tools().execute(f.call("unknown"), context: f.context)
    #expect(result.mcpFields["state"] == .string("unknown")); #expect(await f.driver.executions == 1)
    _ = try await f.tools().execute(f.call("again"), context: f.context)
    #expect(await f.driver.executions == 1)
    let projection = try await f.repository.projection(identity: f.identity)
    let invocation = try #require(projection.invocations.first { $0.state == .unknown })
    try await f.service.resolve(invocationID: invocation.metadata.id, succeeded: true)
    #expect(try await f.tools().availableDefinitions(context: f.context).contains { $0.name == "browser_click" })
    await f.service.suspend()
    let read = try await BrowserFixture(request: "Read-only, no changes"); defer { cleanupWorkspaceTestStorage(read.folder) }
    #expect(try await read.tools().availableDefinitions(context: read.context).contains { $0.name == "browser_snapshot" })
    #expect(try await !read.tools().availableDefinitions(context: read.context).contains { $0.name == "browser_click" })
    await read.service.suspend()
}

@Test func browserPauseStopsTaskScopeAndPreventsFurtherTools() async throws {
    let f = try await BrowserFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let task = try await WorkspaceTaskService(repository: f.repository, identity: f.identity).create(commandID: UUID(), conversationID: f.chat,
        agentID: f.agent, goal: "Read the approved website", executorDeviceID: f.identity.deviceID)
    let lifecycle = WorkspaceTaskLifecycle(repository: f.repository, identity: f.identity)
    #expect(try await lifecycle.claim(task))
    let source = WorkspaceTaskLifecycle.sourceID(taskID: task, workspaceID: f.identity.workspaceID)
    let context = WorkspaceToolContext(sourceMessageID: source, taskID: task, allowedToolIDs: Set(WorkspaceBrowserCatalog.toolIDs), agentID: f.agent)
    let authorized = try await f.service.authorize("browser_snapshot", context: context)
    await f.driver.resetStopped()
    _ = try await f.service.perform(authorized, binding: f.service.prepare(authorized))
    try await lifecycle.pause(commandID: UUID(), taskID: task)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await !f.driver.stopped, ContinuousClock.now < deadline { try await _Concurrency.Task.sleep(for: .milliseconds(20)) }
    #expect(await f.driver.stopped)
    #expect(try await f.tools().availableDefinitions(context: context).isEmpty)
    await f.service.suspend()
}

@Test func automaticBrowserDoesNotRequirePerSiteCredentialsOrAssignments() async throws {
    let f = try await BrowserFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let automatic = WorkspaceBrowserService(repository: f.repository, identity: f.identity, credentials: InaccessibleBrowserCredentials(), driver: f.driver, automaticAccess: true)
    let allowed = try await automatic.authorize("browser_open", context: f.context)
    #expect(allowed.origins == ["*"])
    let tools = try await automatic.availableDefinitions(context: f.context)
    #expect(tools.contains { $0.name == "browser_tabs" })
    #expect(tools.contains { $0.name == "browser_snapshot" })
    await automatic.suspend(); await f.service.suspend()
}
