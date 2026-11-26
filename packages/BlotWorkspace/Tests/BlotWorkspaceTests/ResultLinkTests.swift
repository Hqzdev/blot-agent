import Foundation
import Testing
@testable import BlotWorkspace

@Test func resultLinksOnlyResolveStableArtifactIDs() throws {
    let id = UUID(), url = WorkspaceResultLink.url(for: id)
    #expect(WorkspaceResultLink.artifactID(from: url) == id)
    for raw in ["file:///Users/test/private.txt", "blot-file://not-an-id", url.absoluteString + "/private.txt", url.absoluteString + "?path=/tmp/test", url.absoluteString + "#fragment", "blot-file://user:password@" + id.uuidString] {
        #expect(WorkspaceResultLink.artifactID(from: try #require(URL(string: raw))) == nil)
    }
}

@Test func resultWebsiteCardsComeOnlyFromActualCredentialFreeLinksAndAreBounded() {
    let text = "[Gallery](https://example.com/gallery) [Again](https://example.com/gallery) [Doc](blot-file://" + UUID().uuidString + ") [Secret](https://user:password@example.com/) [Two](https://example.com/two) [Three](https://example.com/three) [Four](https://example.com/four)"
    let cards = WorkspaceResultLink.websites(in: text)
    #expect(cards.count == 3)
    #expect(cards.first?.title == "Gallery")
    #expect(cards.map(\.url.path) == ["/gallery", "/two", "/three"])
    #expect(WorkspaceResultLink.websites(in: "No actual link").isEmpty)
}
