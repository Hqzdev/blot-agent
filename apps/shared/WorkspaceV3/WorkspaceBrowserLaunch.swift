import Foundation

@MainActor
extension WorkspaceStore {
    /// One entry point for a website launch; credentials can only come from the PKCE exchange.
    func handleBrowserLaunch(_ url: URL) {
        openAuthenticationURL(url)
    }
}
