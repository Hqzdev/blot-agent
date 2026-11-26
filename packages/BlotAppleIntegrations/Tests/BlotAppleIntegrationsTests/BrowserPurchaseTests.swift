#if os(macOS)
import AppKit
import BlotWorkspace
import Foundation
import Testing
import WebKit
@testable import BlotAppleIntegrations

@Test @MainActor func purchasePageReviewExcludesSecretInputsAndTracksVisibleOrderChanges() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("blot-purchase-dom-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = NSApplication.shared
    let browser = WorkspaceBrowserController(profileID: UUID(), directory: directory, ephemeral: true)
    defer { browser.shutdown() }
    let tab = BrowserTab(id: UUID(), url: URL(string: "https://fixture.example/checkout"), scope: nil, origins: ["https://fixture.example"])
    let page = BrowserPage(tab: tab, owner: browser, dataStore: .nonPersistent())
    defer { page.stop() }
    page.view.loadHTMLString("<html><body><p id='total'>Total: 100 RUB</p><input type='password' value='secret-password'><input value='private-input'><button id='pay'>Pay now</button></body></html>", baseURL: URL(string: "https://fixture.example/checkout"))
    try await page.waitForLoad()
    let first = try await page.script(BrowserDOM.purchaseReview)
    guard case .string(let text) = first else { Issue.record("Expected page review text"); return }
    #expect(text.contains("100 RUB"))
    #expect(!text.contains("secret-password") && !text.contains("private-input"))
    _ = try await page.script("document.querySelector('#total').textContent='Total: 200 RUB'; return true;")
    let changed = try await page.script(BrowserDOM.purchaseReview)
    #expect(changed != first)
}
#endif
