import BlotWorkspace
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class WorkspaceBrowserController: WorkspaceBrowserExecuting {
    public private(set) var tabs: [BrowserTab] = []
    public private(set) var activeSession: WorkspaceBrowserSessionKey = .workspace
    private var selections: [WorkspaceBrowserSessionKey: UUID] = [:]
    public var selectedID: UUID? { selections[activeSession] }
    public var sessionTabs: [BrowserTab] { tabs.filter { $0.sessionKey == activeSession } }
    @ObservationIgnored private var migratingLegacyTabs = false
    public var presented = false
    public var error: String?
    public var dialog: BrowserDialog?
    public private(set) var downloads: [BrowserDownload] = []
    public let maximumLiveTabs: Int
    @ObservationIgnored let dataStore: WKWebsiteDataStore
    @ObservationIgnored var pages: [UUID: BrowserPage] = [:]
    @ObservationIgnored let downloadsDirectory: URL
    @ObservationIgnored private let stateURL: URL?
    @ObservationIgnored var downloadHandler: BrowserDownloadHandler?
    @ObservationIgnored var busyTabs: Set<UUID> = []
    @ObservationIgnored var stopped = false
    @ObservationIgnored let chooseDownload: (@MainActor @Sendable (String) async -> URL?)?
    public init(profileID: UUID, directory: URL? = nil, ephemeral: Bool = false, maximumLiveTabs: Int? = nil,
                chooseDownload: (@MainActor @Sendable (String) async -> URL?)? = nil) {
        self.chooseDownload = chooseDownload
        #if os(macOS)
        self.maximumLiveTabs = min(2, max(1, maximumLiveTabs ?? 2))
        #else
        self.maximumLiveTabs = 1
        #endif
        dataStore = ephemeral ? .nonPersistent() : WKWebsiteDataStore(forIdentifier: profileID)
        stateURL = directory?.appendingPathComponent("BrowserTabs.json")
        downloadsDirectory = (directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("BlotBrowser-" + profileID.uuidString)).appendingPathComponent("Downloads", isDirectory: true)
        if let stateURL, let data = try? Data(contentsOf: stateURL), data.count <= 512 * 1024 {
            if let saved = try? JSONDecoder().decode(BrowserSavedSession.self, from: data), saved.version == 2 {
                var ids: Set<UUID> = []
                tabs = saved.tabs.prefix(32).compactMap { item in
                    guard ids.insert(item.id).inserted, item.localPage == nil || item.localPage!.utf8.count <= 100,
                          item.url == nil || (try? WorkspaceBrowserURL.validated(item.url!.absoluteString)) != nil else { return nil }
                    let tab = BrowserTab(id: item.id, url: item.url, sessionKey: item.sessionKey, localPage: item.localPage)
                    tab.title = String(item.title.prefix(200)); return tab
                }
                for selection in saved.selections where tabs.contains(where: { $0.id == selection.tabID && $0.sessionKey == selection.key }) {
                    selections[selection.key] = selection.tabID
                }
            } else if let urls = try? JSONDecoder().decode([URL].self, from: data) {
                tabs = urls.prefix(32).compactMap { url in (try? WorkspaceBrowserURL.validated(url.absoluteString)).map { BrowserTab(url: $0) } }
                selections[.workspace] = tabs.first?.id; migratingLegacyTabs = !tabs.isEmpty
            }
        }
    }
    public func activateSession(_ key: WorkspaceBrowserSessionKey) {
        guard key != activeSession else { return }
        if migratingLegacyTabs, key != .workspace {
            for tab in tabs where tab.sessionKey == .workspace { tab.sessionKey = key }
            selections[key] = selections.removeValue(forKey: .workspace); migratingLegacyTabs = false
        }
        dialog?.finish(accepted: false); dialog = nil
        activeSession = key
        if selections[key] == nil { selections[key] = sessionTabs.first?.id }
        saveTabs()
    }
    func selectedID(in session: WorkspaceBrowserSessionKey) -> UUID? { selections[session] }
    public var selectedTab: BrowserTab? { tabs.first { $0.id == selectedID } }
    public var sessionDownloads: [BrowserDownload] { downloads.filter { $0.sessionKey == activeSession } }
    public var liveTabCount: Int { pages.count }
    public func webView(for id: UUID) -> WKWebView? { pages[id]?.view }
    @discardableResult public func open(_ raw: String) throws -> UUID {
        guard !stopped, tabs.count < 32 else { throw WorkspaceBrowserError.busy }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try WorkspaceBrowserURL.validated(text.contains("://") ? text : "https://" + text)
        let tab = BrowserTab(url: url, sessionKey: activeSession); try createPage(tab)
        tabs.append(tab); selections[activeSession] = tab.id; presented = true
        pages[tab.id]?.load(url); saveTabs(); return tab.id
    }
    public func select(_ id: UUID) throws {
        guard !stopped, let tab = tabs.first(where: { $0.id == id }) else { throw WorkspaceBrowserError.unavailable }
        guard tab.sessionKey == activeSession else { throw WorkspaceBrowserError.denied }
        try activatePage(tab); selections[activeSession] = id; saveTabs()
    }
    func activatePage(_ tab: BrowserTab) throws {
        let wasLive = pages[tab.id] != nil
        if tab.url != nil { try createPage(tab) }; tab.lastUsed = Date()
        if !wasLive, let url = tab.url { pages[tab.id]?.load(url) }
    }
    public func navigate(_ raw: String, tabID: UUID) throws {
        guard let tab = tabs.first(where: { $0.id == tabID }), !tab.unsaved else { throw WorkspaceBrowserError.unsavedChanges }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try WorkspaceBrowserURL.validated(text.contains("://") ? text : "https://" + text)
        try select(tabID)
        tab.localPage = nil
        try createPage(tab)
        guard permits(url, tab: tab) else { throw WorkspaceBrowserError.denied }
        tab.stopped = false; pages[tabID]?.load(url)
    }
    public func close(_ id: UUID, discard: Bool = false) throws {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.unsaved && !discard { throw WorkspaceBrowserError.unsavedChanges }
        dialog?.finish(accepted: false)
        pages.removeValue(forKey: id)?.detach(); busyTabs.remove(id)
        for item in downloads where item.tabID == id && item.state == "running" { item.download.cancel(nil); item.state = "canceled" }
        tabs.removeAll { $0.id == id }
        if selections[tab.sessionKey] == id {
            selections[tab.sessionKey] = tabs.last { $0.sessionKey == tab.sessionKey }?.id
            if tab.sessionKey == activeSession, let selectedID { try? select(selectedID) }
        }
        saveTabs()
    }
    public func back(_ id: UUID, forward: Bool = false) throws {
        guard let tab = tabs.first(where: { $0.id == id }), !tab.unsaved, let page = pages[id] else { throw WorkspaceBrowserError.unsavedChanges }
        if forward { page.view.goForward() } else { page.view.goBack() }
    }
    public func reload(_ id: UUID) throws {
        guard let tab = tabs.first(where: { $0.id == id }), !tab.unsaved else { throw WorkspaceBrowserError.unsavedChanges }
        if tab.loading { pages[id]?.stop() } else { pages[id]?.view.reload() }
    }
    public func stop(scope: WorkspaceBrowserScope?) {
        for tab in tabs where scope == nil || tab.scope == scope {
            pages[tab.id]?.stop(); tab.loading = false
            if tab.scope != nil { tab.stopped = true }
            for item in downloads where item.tabID == tab.id && item.state == "running" { item.download.cancel(nil); item.state = "canceled" }
        }
    }
    public func shutdown() {
        dialog?.finish(accepted: false); dialog = nil
        stopped = true; stop(scope: nil)
        for item in downloads where item.state == "running" { item.download.cancel(nil); item.state = "canceled" }
        for page in pages.values { page.detach() }; pages.removeAll(); tabs.removeAll(); selections.removeAll(); presented = false
    }
    public func resume() { stopped = false }
    public func newTab() throws {
        guard !stopped, tabs.count < 32 else { throw WorkspaceBrowserError.busy }
        tabsAppend(BrowserTab(sessionKey: activeSession))
    }
    @discardableResult public func openLocalPage(_ page: String, title: String, replacing id: UUID? = nil) throws -> UUID {
        guard !stopped, page.utf8.count <= 100 else { throw WorkspaceBrowserError.unavailable }
        if let id, let tab = sessionTabs.first(where: { $0.id == id && $0.url == nil }) {
            tab.localPage = page; tab.title = title; selections[activeSession] = id; saveTabs(); return id
        }
        guard tabs.count < 32 else { throw WorkspaceBrowserError.busy }
        let tab = BrowserTab(sessionKey: activeSession, localPage: page); tab.title = title
        tabsAppend(tab); return tab.id
    }
    public func discardForm(_ id: UUID) { tabs.first { $0.id == id }?.unsaved = false }
    func permits(_ url: URL, tab: BrowserTab) -> Bool {
        guard (try? WorkspaceBrowserURL.validated(url.absoluteString)) != nil else { return false }
        return tab.scope == nil || tab.allowedOrigins.contains("*") || ((try? WorkspaceBrowserURL.origin(url)).map(tab.allowedOrigins.contains) == true)
    }
    func createPage(_ tab: BrowserTab) throws {
        if pages[tab.id] != nil { return }
        if pages.count >= maximumLiveTabs {
            guard let victim = tabs.filter({ tab in pages[tab.id] != nil && !tab.unsaved && !busyTabs.contains(tab.id) && !downloads.contains(where: { $0.tabID == tab.id && $0.state == "running" }) }).min(by: { $0.lastUsed < $1.lastUsed }) else { throw WorkspaceBrowserError.busy }
            pages.removeValue(forKey: victim.id)?.detach(); victim.isLive = false; victim.loading = false
        }
        let page = BrowserPage(tab: tab, owner: self, dataStore: dataStore)
        pages[tab.id] = page; tab.isLive = true; tab.lastUsed = Date()
    }
    func saveTabs() {
        guard let stateURL else { return }
        do {
            let records = tabs.filter { $0.scope == nil }.map { tab in
                BrowserSavedSession.Tab(id: tab.id, sessionKey: tab.sessionKey, url: tab.url.flatMap(WorkspaceBrowserURL.restorable), localPage: tab.localPage, title: String(tab.title.prefix(200)))
            }
            let saved = BrowserSavedSession(version: 2, tabs: records, selections: selections.map { .init(key: $0.key, tabID: $0.value) })
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: stateURL, options: .atomic)
        } catch { self.error = "Не удалось сохранить список вкладок." }
    }
    func tabsAppend(_ tab: BrowserTab) {
        guard tabs.count < 32 else { pages.removeValue(forKey: tab.id)?.detach(); error = WorkspaceBrowserError.busy.localizedDescription; return }
        tabs.append(tab); selections[tab.sessionKey] = tab.id
        if tab.sessionKey == activeSession { presented = true }; saveTabs()
    }
    func beginDownload(_ download: WKDownload, tabID: UUID) {
        if downloadHandler == nil { downloadHandler = BrowserDownloadHandler(owner: self) }
        if downloads.count >= 100 { downloads.removeAll { $0.state != "running" } }
        let item = BrowserDownload(download, tabID: tabID, sessionKey: tabs.first { $0.id == tabID }?.sessionKey ?? activeSession); downloads.append(item); download.delegate = downloadHandler
    }
    public func cancelDownload(_ id: UUID) {
        guard let item = downloads.first(where: { $0.id == id }), item.state == "running" else { return }
        item.download.cancel(nil); item.state = "canceled"
    }
}

private struct BrowserSavedSession: Codable {
    let version: Int
    let tabs: [Tab]
    let selections: [Selection]
    struct Tab: Codable {
        let id: UUID
        let sessionKey: WorkspaceBrowserSessionKey
        let url: URL?
        let localPage: String?
        let title: String
    }
    struct Selection: Codable { let key: WorkspaceBrowserSessionKey; let tabID: UUID }
}
