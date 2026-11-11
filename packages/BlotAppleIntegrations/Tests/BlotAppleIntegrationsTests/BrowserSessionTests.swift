import BlotWorkspace
import Foundation
import Testing
@testable import BlotAppleIntegrations

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
