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
    @discardableResult func ensureBrowser() -> WorkspaceBrowserController {
        if let controller = browserCommands?.workspaceBrowser { controller.activateSession(browserSessionKey); return controller }
        if let controller = guestBrowser.controller { controller.activateSession(browserSessionKey); return controller }
        let controller = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
        guestBrowser.controller = controller; controller.activateSession(browserSessionKey); return controller
    }
    func showBrowser() {
        let controller = ensureBrowser()
        if controller.selectedTab?.localPage != nil { try? controller.newTab() }
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
    func openBrowserURL(_ url: URL) {
        let browser = ensureBrowser()
        do { _ = try browser.open(url.absoluteString); presentBrowser(browser) }
        catch { self.error = error.localizedDescription }
    }
    private func presentBrowser(_ browser: WorkspaceBrowserController) {
        browser.presented = true
        #if os(macOS)
        if snapshot.ownerID != nil && !route.isAuthentication && ![.home, .newChat, .chat, .browser].contains(route) {
            settingsRoute = nil; navigate(.browser)
        } else if settingsRoute != nil {
            settingsRoute = nil
        }
        #endif
    }
}
