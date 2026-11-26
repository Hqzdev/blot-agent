import BlotWorkspace
import Foundation
import Testing
@testable import BlotAppleIntegrations
#if os(macOS)
import AppKit
#endif

@Test @MainActor func agentTabsRestoreSelectionAndNeverMixWithOtherAgentsOrGroups() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("blot-session-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = WorkspaceBrowserSessionKey.agent(UUID()), second = WorkspaceBrowserSessionKey.agent(UUID()), group = WorkspaceBrowserSessionKey.group(UUID())
    let browser = WorkspaceBrowserController(profileID: UUID(), directory: folder, ephemeral: true)
    defer { browser.shutdown() }
    browser.activateSession(first)
    let files = try browser.openLocalPage("page:files", title: "Files")
    let skills = try browser.openLocalPage("page:skills", title: "Skills")
    try browser.select(files)
    browser.activateSession(second)
    #expect(browser.sessionTabs.isEmpty)
    let memory = try browser.openLocalPage("page:memory", title: "Memory")
    browser.activateSession(group)
    let tasks = try browser.openLocalPage("page:running", title: "Tasks")
    browser.activateSession(first)
    #expect(browser.selectedID == files)
    #expect(browser.sessionTabs.map(\.id) == [files, skills])
    #expect(throws: WorkspaceBrowserError.denied) { try browser.select(memory) }
    #expect(browser.liveTabCount == 0)

    let restored = WorkspaceBrowserController(profileID: UUID(), directory: folder, ephemeral: true)
    defer { restored.shutdown() }
    restored.activateSession(first)
    #expect(restored.selectedID == files)
    #expect(restored.sessionTabs.map(\.localPage) == ["page:files", "page:skills"])
    try restored.close(files)
    #expect(restored.selectedID == skills)
    restored.activateSession(second)
    #expect(restored.selectedID == memory)
    restored.activateSession(group)
    #expect(restored.sessionTabs.map(\.id) == [tasks])
    #expect(restored.liveTabCount == 0)
}

@Test @MainActor func legacyTabHistoryIsAdoptedOnceWithoutLeakingToEveryAgent() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("blot-legacy-tabs-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONEncoder().encode([URL(string: "https://example.com/docs")!]).write(to: folder.appendingPathComponent("BrowserTabs.json"))
    let browser = WorkspaceBrowserController(profileID: UUID(), directory: folder, ephemeral: true)
    defer { browser.shutdown() }
    let first = WorkspaceBrowserSessionKey.agent(UUID())
    browser.activateSession(first)
    #expect(browser.sessionTabs.count == 1)
    #expect(browser.selectedTab?.url?.path == "/docs")
    browser.activateSession(.agent(UUID()))
    #expect(browser.sessionTabs.isEmpty)
    browser.activateSession(first)
    #expect(browser.sessionTabs.count == 1)
    #expect(browser.liveTabCount == 0)
}

#if os(macOS)
@Test @MainActor func browserAttachmentUsesTheLiveUserTabAndExpiresWithTheRun() async throws {
    _ = NSApplication.shared
    let browser = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
    defer { browser.shutdown() }
    let agentID = UUID()
    let scope = WorkspaceBrowserScope(sourceID: UUID(), taskID: nil, agentID: agentID)
    let session = WorkspaceBrowserSessionKey.agent(agentID)
    browser.activateSession(session)
    let url = try WorkspaceBrowserURL.validated("https://fixture.example/")
    let tab = BrowserTab(url: url, sessionKey: session)
    try browser.createPage(tab)
    browser.tabsAppend(tab, presentsBrowser: false)
    let page = try #require(browser.pages[tab.id])
    tab.loading = true
    page.view.loadHTMLString("""
        <form><input id="query" type="search" aria-label="Search">
        <input type="hidden" name="_csrf" value="private">
        <button type="button" onclick="document.querySelector('#result').textContent='clicked'">Apply</button></form>
        <p id="result"></p>
        """, baseURL: url)
    try await page.waitForLoad()

    func command(_ name: String, _ fields: [String: ChatJSON] = [:]) -> WorkspaceBrowserCommand {
        var arguments = fields
        arguments["tab_id"] = .string(tab.id.uuidString)
        if arguments["document_id"] == nil { arguments["document_id"] = .string(tab.documentID.uuidString) }
        return .init(id: UUID(), name: name, arguments: .object(arguments), scope: scope, origins: ["https://fixture.example"], sessionKey: session)
    }
    let snapshot = command("browser_snapshot")
    let scroll = command("browser_scroll")
    await #expect(throws: WorkspaceBrowserError.denied) { _ = try await browser.prepare(scroll) }
    let initial = try await browser.execute(snapshot, binding: browser.prepare(snapshot))
    guard case .value(.object(let fields)) = initial, case .array(let elements) = fields["elements"] else {
        Issue.record("Expected the live page snapshot")
        return
    }
    #expect(fields["access"] == .string("read_only"))
    #expect(browser.agentSiteTab?.id == tab.id)
    #expect(!browser.presented)
    guard case .object(let searchField) = elements.first, let search = searchField["id"] else {
        Issue.record("Expected a searchable text field")
        return
    }
    let staleAttach = command("browser_attach", ["document_id": .string(UUID().uuidString)])
    await #expect(throws: WorkspaceBrowserError.stalePage) { _ = try await browser.prepare(staleAttach) }
    let attach = WorkspaceBrowserCommand(id: UUID(), name: "browser_attach", arguments: .object([:]), scope: scope,
        origins: ["https://fixture.example"], sessionKey: session)
    let attachBinding = try await browser.prepare(attach)
    try browser.newTab()
    await #expect(throws: WorkspaceBrowserError.denied) { _ = try await browser.execute(attach, binding: attachBinding) }
    try browser.select(tab.id)
    browser.presented = false
    _ = try await browser.execute(attach, binding: attachBinding)
    #expect(browser.webView(for: tab.id) === page.view)
    #expect(!browser.presented)
    #expect(!browser.permitsAgentNavigation(URL(string: "https://other.example/")!, tab: tab))
    await #expect(throws: WorkspaceBrowserError.denied) { _ = try await browser.prepare(command("browser_close")) }

    let type = command("browser_type", ["element_id": search, "text": .string("exact text")])
    let staleAfterPause = try await browser.prepare(type)
    browser.pauseAgent()
    browser.resumeAgent()
    await #expect(throws: WorkspaceBrowserError.stalePage) { _ = try await browser.execute(type, binding: staleAfterPause) }
    _ = try await browser.execute(type, binding: browser.prepare(type))
    #expect(try await page.script("return document.querySelector('#query').value;") == .string("exact text"))
    let refreshed = try await browser.execute(snapshot, binding: browser.prepare(snapshot))
    guard case .value(.object(let updatedFields)) = refreshed, case .array(let updatedElements) = updatedFields["elements"],
          case .object(let applyButton) = updatedElements.last, let buttonID = applyButton["id"] else {
        Issue.record("Expected the apply button after input")
        return
    }
    let click = command("browser_click", ["element_id": buttonID])
    let staleClick = try await browser.prepare(click)
    _ = try await page.script("document.querySelector('button').textContent='Renamed'; return true;")
    await #expect(throws: WorkspaceBrowserError.stalePage) { _ = try await browser.execute(click, binding: staleClick) }
    #expect(try await page.script("return document.querySelector('#result').textContent;") == .string(""))
    _ = try await browser.execute(click, binding: browser.prepare(click))
    #expect(try await page.script("return document.querySelector('#result').textContent;") == .string("clicked"))
    #expect(!browser.presented)

    try browser.newTab()
    #expect(browser.selectedID != tab.id)
    _ = try await browser.execute(scroll, binding: browser.prepare(scroll))
    browser.finishRun(taskID: nil, sourceID: scope.sourceID)
    await #expect(throws: WorkspaceBrowserError.denied) { _ = try await browser.prepare(scroll) }
    #expect(browser.webView(for: tab.id) === page.view)
}
#endif
