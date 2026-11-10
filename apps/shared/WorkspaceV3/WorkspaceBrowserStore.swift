import BlotAppleIntegrations
import BlotWorkspace
import Foundation

@MainActor
extension WorkspaceStore {
    var browserCommands: (any WorkspaceBrowserProviding)? { (serviceForBrowser as? any WorkspaceBrowserProviding) }
    var browser: WorkspaceBrowserController? { browserCommands?.browserSession.controller ?? guestBrowser.controller }
    @discardableResult func ensureBrowser() -> WorkspaceBrowserController {
        if let controller = browserCommands?.workspaceBrowser { return controller }
        if let controller = guestBrowser.controller { return controller }
        let controller = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
        guestBrowser.controller = controller; return controller
    }
    func showBrowser() {
        presentBrowser(ensureBrowser())
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
