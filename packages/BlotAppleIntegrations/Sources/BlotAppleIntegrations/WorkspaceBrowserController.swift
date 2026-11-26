import BlotWorkspace
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class WorkspaceBrowserController: WorkspaceBrowserExecuting {
    public internal(set) var profiles: [WorkspaceBrowserProfileInfo]
    let legacyProfileID: UUID
    var sessionProfiles: [WorkspaceBrowserSessionKey: UUID] = [:]
    public private(set) var tabs: [BrowserTab] = []
    public private(set) var activeSession: WorkspaceBrowserSessionKey = .workspace
    private var selections: [WorkspaceBrowserSessionKey: UUID] = [:]
    private var agentTabs: [WorkspaceBrowserSessionKey: UUID] = [:]
    public var selectedID: UUID? { selections[activeSession] }
    public var agentPaused: Bool { manualSessions.contains(activeSession) }
    public var agentHasControl: Bool {
        sessionTabs.contains { attachments[$0.id] != nil || ($0.scope != nil && !$0.stopped) }
    }
    public func pauseAgent() {
        pauseAgent(in: activeSession)
    }
    public func resumeAgent() { manualSessions.remove(activeSession) }
    func pauseAgent(in session: WorkspaceBrowserSessionKey) {
        manualSessions.insert(session)
        for tab in tabs where tab.sessionKey == session {
            tab.interactionRevision += 1
            tab.agentPointer = nil
        }
    }
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
    var manualSessions: Set<WorkspaceBrowserSessionKey> = []
    struct Attachment {
        let scope: WorkspaceBrowserScope
        let origin: String
    }
    var attachments: [UUID: Attachment] = [:]
    @ObservationIgnored var stopped = false
    @ObservationIgnored let chooseDownload: (@MainActor @Sendable (String) async -> URL?)?
    public init(profileID: UUID, directory: URL? = nil, ephemeral: Bool = false, maximumLiveTabs: Int? = nil,
                chooseDownload: (@MainActor @Sendable (String) async -> URL?)? = nil) {
        self.legacyProfileID = profileID
        self.profiles = [.init(id: profileID, name: "Ori")]
        self.chooseDownload = chooseDownload
        self.maximumLiveTabs = min(2, max(1, maximumLiveTabs ?? 2))
        dataStore = ephemeral ? .nonPersistent() : WKWebsiteDataStore(forIdentifier: profileID)
        stateURL = directory?.appendingPathComponent("BrowserTabs.json")
        downloadsDirectory = (directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("BlotBrowser-" + profileID.uuidString)).appendingPathComponent("Downloads", isDirectory: true)
        if let stateURL, let data = try? Data(contentsOf: stateURL), data.count <= 512 * 1024 {
            if let saved = try? JSONDecoder().decode(BrowserSavedSession.self, from: data), saved.version == 2 {
                if let savedProfiles = saved.profiles, savedProfiles.count <= 16, Set(savedProfiles.map(\.id)).count == savedProfiles.count {
                    profiles = [.init(id: profileID, name: "Ori")] + savedProfiles.filter { $0.id != profileID }
                }
                for selection in saved.profileSelections ?? [] where profiles.contains(where: { $0.id == selection.profileID }) {
                    sessionProfiles[selection.key] = selection.profileID
                }
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
    public var agentSiteTab: BrowserTab? {
        guard let id = agentTabs[activeSession] else { return nil }
        return sessionTabs.first { $0.id == id && $0.url?.host != nil }
    }
    func noteAgentSite(_ tab: BrowserTab) { agentTabs[tab.sessionKey] = tab.id }
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
        revokeAttachmentIfLeaving(tab, url: url)
        tab.localPage = nil
        try createPage(tab)
        guard permits(url, tab: tab) else { throw WorkspaceBrowserError.denied }
        tab.stopped = false; pages[tabID]?.load(url)
    }
    public func close(_ id: UUID, discard: Bool = false) throws {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.unsaved && !discard { throw WorkspaceBrowserError.unsavedChanges }
        dialog?.finish(accepted: false)
        detachAgent(from: tab)
        pages.removeValue(forKey: id)?.detach(); busyTabs.remove(id)
        for item in downloads where item.tabID == id && item.state == "running" { item.download.cancel(nil); item.state = "canceled" }
        tabs.removeAll { $0.id == id }
        if agentTabs[tab.sessionKey] == id { agentTabs.removeValue(forKey: tab.sessionKey) }
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
        for tab in tabs where scope == nil || tab.scope == scope || attachments[tab.id]?.scope == scope {
            detachAgent(from: tab)
            pages[tab.id]?.stop(); tab.loading = false
            if tab.scope != nil { tab.stopped = true }
            for item in downloads where item.tabID == tab.id && item.state == "running" { item.download.cancel(nil); item.state = "canceled" }
        }
    }
    public func finishRun(taskID: UUID?, sourceID: UUID?) {
        guard taskID != nil || sourceID != nil else { return }
        func matches(_ scope: WorkspaceBrowserScope?) -> Bool {
            guard let scope else { return false }
            if let taskID { return scope.taskID == taskID }
            return scope.taskID == nil && scope.sourceID == sourceID
        }
        for tab in tabs {
            if matches(attachments[tab.id]?.scope) { detachAgent(from: tab) }
            if matches(tab.scope) {
                detachAgent(from: tab)
                tab.scope = nil
                tab.allowedOrigins = []
                tab.stopped = false
            }
        }
        saveTabs()
    }
    func detachAgent(from tab: BrowserTab) {
        attachments.removeValue(forKey: tab.id)
        tab.interactionRevision += 1
        tab.agentPointer = nil
    }
    func revokeAttachmentIfLeaving(_ tab: BrowserTab, url: URL) {
        if let attachment = attachments[tab.id], (try? WorkspaceBrowserURL.origin(url)) != attachment.origin {
            detachAgent(from: tab)
        }
    }
    func permitsAgentNavigation(_ url: URL, tab: BrowserTab) -> Bool {
        guard let attachment = attachments[tab.id] else { return true }
        if manualSessions.contains(tab.sessionKey) {
            revokeAttachmentIfLeaving(tab, url: url)
            return true
        }
        return (try? WorkspaceBrowserURL.origin(url)) == attachment.origin
    }
    public func shutdown() {
        dialog?.finish(accepted: false); dialog = nil
        stopped = true; stop(scope: nil)
        for item in downloads where item.state == "running" { item.download.cancel(nil); item.state = "canceled" }
        for page in pages.values { page.detach() }; pages.removeAll(); tabs.removeAll(); selections.removeAll(); agentTabs.removeAll(); presented = false
    }
    public static func eraseSavedProfiles(directory: URL) async {
        let file = directory.appendingPathComponent("Browser/BrowserTabs.json")
        guard let data = try? Data(contentsOf: file), data.count <= 512 * 1024,
              let saved = try? JSONDecoder().decode(BrowserSavedSession.self, from: data) else { return }
        for profile in (saved.profiles ?? []).dropFirst() {
            await WKWebsiteDataStore(forIdentifier: profile.id).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
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
    public func setLocalDocumentUnsaved(_ id: UUID, _ dirty: Bool) {
        guard let tab = tabs.first(where: { $0.id == id }), (tab.localPage == "page:file" || tab.localPage?.hasPrefix("page:file:") == true) else { return }
        tab.unsaved = dirty
    }
    public func discardForm(_ id: UUID) { tabs.first { $0.id == id }?.unsaved = false }
    func permits(_ url: URL, tab: BrowserTab) -> Bool {
        guard (try? WorkspaceBrowserURL.validated(url.absoluteString)) != nil else { return false }
        return tab.scope == nil || tab.allowedOrigins.contains("*") || ((try? WorkspaceBrowserURL.origin(url)).map(tab.allowedOrigins.contains) == true)
    }
    func createPage(_ tab: BrowserTab) throws {
        if pages[tab.id] != nil { return }
        if pages.count >= maximumLiveTabs {
            guard let victim = tabs.filter({ tab in pages[tab.id] != nil && !tab.unsaved && attachments[tab.id] == nil && !busyTabs.contains(tab.id) && !downloads.contains(where: { $0.tabID == tab.id && $0.state == "running" }) }).min(by: { $0.lastUsed < $1.lastUsed }) else { throw WorkspaceBrowserError.busy }
            pages.removeValue(forKey: victim.id)?.detach(); victim.isLive = false; victim.loading = false
        }
        let page = BrowserPage(tab: tab, owner: self, dataStore: store(for: tab.sessionKey))
        pages[tab.id] = page; tab.isLive = true; tab.lastUsed = Date()
    }
    func saveTabs() {
        guard let stateURL else { return }
        do {
            let records = tabs.filter { $0.scope == nil }.map { tab in
                BrowserSavedSession.Tab(id: tab.id, sessionKey: tab.sessionKey, url: tab.url.flatMap(WorkspaceBrowserURL.restorable), localPage: tab.localPage, title: String(tab.title.prefix(200)))
            }
            let saved = BrowserSavedSession(version: 2, tabs: records, selections: selections.map { .init(key: $0.key, tabID: $0.value) }, profiles: profiles, profileSelections: sessionProfiles.map { .init(key: $0.key, profileID: $0.value) })
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: stateURL, options: .atomic)
        } catch { self.error = "Не удалось сохранить список вкладок." }
    }
    func tabsAppend(_ tab: BrowserTab, presentsBrowser: Bool = true) {
        guard tabs.count < 32 else { pages.removeValue(forKey: tab.id)?.detach(); error = WorkspaceBrowserError.busy.localizedDescription; return }
        tabs.append(tab); selections[tab.sessionKey] = tab.id
        if presentsBrowser, tab.sessionKey == activeSession { presented = true }
        saveTabs()
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
    let profiles: [WorkspaceBrowserProfileInfo]?
    let profileSelections: [ProfileSelection]?
    struct ProfileSelection: Codable { let key: WorkspaceBrowserSessionKey; let profileID: UUID }
    struct Tab: Codable {
        let id: UUID
        let sessionKey: WorkspaceBrowserSessionKey
        let url: URL?
        let localPage: String?
        let title: String
    }
    struct Selection: Codable { let key: WorkspaceBrowserSessionKey; let tabID: UUID }
}
