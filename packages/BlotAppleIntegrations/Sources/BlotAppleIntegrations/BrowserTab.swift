import BlotWorkspace
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class BrowserTab: Identifiable {
    public let id: UUID
    public internal(set) var sessionKey: WorkspaceBrowserSessionKey
    public internal(set) var localPage: String?
    let initialURL: URL?
    public internal(set) var title = "Новая вкладка"
    public internal(set) var url: URL?
    public internal(set) var loading = false
    public internal(set) var progress = 0.0
    public internal(set) var canGoBack = false
    public internal(set) var canGoForward = false
    public internal(set) var unsaved = false
    public internal(set) var isLive = false
    public internal(set) var error: String?
    public internal(set) var authenticationURL: URL?
    public internal(set) var documentID = UUID()
    var interactionRevision = 0
    var sensitiveInput = false
    @ObservationIgnored var scope: WorkspaceBrowserScope?
    @ObservationIgnored var allowedOrigins: Set<String> = []
    @ObservationIgnored var lastUsed = Date()
    @ObservationIgnored var stopped = false
    init(id: UUID = UUID(), url: URL? = nil, scope: WorkspaceBrowserScope? = nil, origins: Set<String> = [], sessionKey: WorkspaceBrowserSessionKey = .workspace, localPage: String? = nil) {
        self.id = id; self.url = url; initialURL = url; self.scope = scope; allowedOrigins = origins; self.sessionKey = sessionKey; self.localPage = localPage
    }
}

@MainActor @Observable
public final class BrowserDownload: Identifiable {
    public let sessionKey: WorkspaceBrowserSessionKey
    public let id = UUID()
    public internal(set) var name = "Загрузка"
    public internal(set) var state = "running"
    public internal(set) var url: URL?
    public internal(set) var error: String?
    @ObservationIgnored let download: WKDownload
    @ObservationIgnored let tabID: UUID
    init(_ download: WKDownload, tabID: UUID, sessionKey: WorkspaceBrowserSessionKey) { self.download = download; self.tabID = tabID; self.sessionKey = sessionKey }
}
