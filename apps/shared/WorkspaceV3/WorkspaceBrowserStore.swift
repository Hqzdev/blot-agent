import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

@MainActor
extension WorkspaceStore {
    var browserCommands: (any WorkspaceBrowserProviding)? { (serviceForBrowser as? any WorkspaceBrowserProviding) }
    var browserSessionKey: WorkspaceBrowserSessionKey {
        if let chat = currentConversation, chat.kind == .group { return .group(chat.metadata.id) }
        return (currentConversation?.agentId ?? selectedAgentID).map { .agent($0) } ?? .workspace
    }
    var browser: WorkspaceBrowserController? { browserCommands?.browserSession.controller ?? guestBrowser.controller }
    func updateBrowserSession() {
        let state = browserCommands?.browserSession ?? guestBrowser
        state.selectSession(browserSessionKey)
    }
    @discardableResult func ensureBrowser() -> WorkspaceBrowserController {
        updateBrowserSession()
        if let controller = browserCommands?.workspaceBrowser ?? guestBrowser.controller { return controller }
        let controller = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
        controller.activateSession(guestBrowser.activeSession)
        guestBrowser.controller = controller; return controller
    }
    func showBrowser() {
        let controller = ensureBrowser()
        if controller.selectedTab?.localPage != nil { try? controller.newTab() }
        presentBrowser(controller)
    }
    func showBrowserTab(_ id: UUID) throws {
        let controller = ensureBrowser()
        try controller.select(id)
        presentBrowser(controller)
    }
    func toggleToolsPanel() {
        let controller = ensureBrowser()
        if controller.presented { controller.presented = false; return }
        do {
            if controller.sessionTabs.isEmpty { try controller.newTab() }
            presentBrowser(controller)
        } catch { self.error = error.localizedDescription }
    }
    func showTools() {
        let controller = ensureBrowser()
        do {
            if let blank = controller.sessionTabs.first(where: { $0.url == nil && ($0.localPage == nil || $0.localPage == "start") }) { try controller.select(blank.id) }
            else { try controller.newTab() }
            presentBrowser(controller)
        } catch { self.error = error.localizedDescription }
    }
    func showGeneratedFile(_ id: UUID, editing: Bool = false) {
        guard let file = snapshot.artifacts.first(where: { $0.metadata.id == id }) else { return }
        documentOpeningModes[id] = editing
        documentEdits[id]?.editing = editing
        #if os(macOS)
        let controller = ensureBrowser()
        do {
            if let tab = controller.sessionTabs.first(where: { panelNavigations.navigation(for: $0).fileID == id }) {
                try controller.select(tab.id); presentBrowser(controller); return
            }
            let tabID = try controller.openLocalPage("page:file:" + id.uuidString, title: file.name)
            let navigation = panelNavigations.navigation(for: controller.tabs.first { $0.id == tabID })
            navigation.fileID = id
            navigation.path = [.page(.file)]
            presentBrowser(controller)
        } catch { self.error = error.localizedDescription }
        #else
        selectedRecordID = id
        navigate(.file)
        #endif
    }
    func showFileChange(_ id: UUID, title: String) {
        let controller = ensureBrowser()
        do {
            let page = WorkspaceToolDestination.fileChange(id)
            if let tab = controller.sessionTabs.first(where: { $0.localPage == page.identifier }) { try controller.select(tab.id) }
            else { _ = try controller.openLocalPage(page.identifier, title: (title as NSString).lastPathComponent) }
            presentBrowser(controller)
        } catch { self.error = error.localizedDescription }
    }
    #if os(macOS)
    func showChanges(_ source: WorkspaceChangesSource) {
        let controller = ensureBrowser()
        let page = WorkspaceToolDestination.changes(source)
        do {
            if let tab = controller.sessionTabs.first(where: { $0.localPage == page.identifier }) {
                try controller.select(tab.id)
            } else {
                _ = try controller.openLocalPage(page.identifier, title: page.title(russian: language == "ru"))
            }
            presentBrowser(controller)
        } catch { self.error = error.localizedDescription }
    }
    #endif
    func openBrowserURL(_ url: URL) {
        #if os(iOS)
        if !PhoneLinkBrowser.open(url) {
            error = language == "ru" ? "Не удалось открыть ссылку." : "Could not open the link."
        }
        #else
        let browser = ensureBrowser()
        do { _ = try browser.open(url.absoluteString); presentBrowser(browser) }
        catch { self.error = error.localizedDescription }
        #endif
    }
    private func presentBrowser(_ browser: WorkspaceBrowserController) {
        browser.presented = true
        #if os(iOS)
        if route != .browser { navigate(.browser) }
        #else
        if snapshot.ownerID != nil && !route.isAuthentication && ![.home, .newChat, .chat, .browser].contains(route) {
            settingsRoute = nil; navigate(.browser)
        } else if settingsRoute != nil {
            settingsRoute = nil
        }
        #endif
    }
}
