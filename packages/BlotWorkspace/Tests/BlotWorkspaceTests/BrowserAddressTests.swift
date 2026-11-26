import Foundation
import Testing
@testable import BlotWorkspace

@Test func browserAddressBarSearchesWordsAndKeepsAddressesInsideTheBrowser() throws {
    for query in ["гитхаб", "github", "swift apple", "c++ & swift", "https documentation"] {
        let url = try WorkspaceBrowserURL.userNavigation(query)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "www.google.com" && parts.path == "/search")
        #expect(parts.queryItems?.first(where: { $0.name == "q" })?.value == query)
    }
    #expect(try WorkspaceBrowserURL.userNavigation(" github.com/openai ").absoluteString == "https://github.com/openai")
    #expect(try WorkspaceBrowserURL.userNavigation("localhost:8080/test").absoluteString == "http://localhost:8080/test")
    #expect(try WorkspaceBrowserURL.userNavigation("https://example.com/?q=hello").host == "example.com")
    for invalid in ["", "  ", "javascript:alert(1)", "data:text/html,test", "file:///etc/passwd", "mailto:person@example.com", "https://name:secret@example.com", "http://example.com"] {
        #expect(throws: WorkspaceBrowserError.self) { _ = try WorkspaceBrowserURL.userNavigation(invalid) }
    }
    // Search interpretation must not weaken the URL-only contract used by agents.
    #expect(throws: WorkspaceBrowserError.self) { _ = try WorkspaceBrowserURL.validated("гитхаб") }
}
