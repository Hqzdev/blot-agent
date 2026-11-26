import BlotDomain
import Foundation

public enum WorkspaceGooglePlugin: String, CaseIterable, Sendable, Codable {
    case gmail, calendar, drive
    public var name: String { switch self { case .gmail: "Gmail"; case .calendar: "Google Calendar"; case .drive: "Google Drive" } }
    public var access: Set<GoogleAccess> {
        switch self { case .gmail: [.gmailRead, .gmailDrafts, .gmailSend]; case .calendar: [.calendarList, .calendarRead, .calendarWrite, .calendarFreeBusy]; case .drive: [.driveRead, .driveFile] }
    }
}
public struct WorkspaceGoogleAccount: Codable, Sendable, Identifiable {
    public let id: UUID
    public let plugin: WorkspaceGooglePlugin
    public let email: String
    var configuration: StoredConfiguration
    var tokens: GoogleOAuthTokens
    struct StoredConfiguration: Codable, Sendable { let clientID: String; let redirectURI: URL; var clientSecret: String? = nil }
}

public actor WorkspaceGoogleService {
    private let identity: WorkspaceIdentity
    private let repository: WorkspaceRepository
    private let credentials: any WorkspaceCredentialStore
    private let session: URLSession
    private var mutating = false
    private var suspended = false
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore, session: URLSession? = nil) {
        self.identity = identity; self.repository = repository; self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 60
        self.session = session ?? URLSession(configuration: configuration, delegate: GoogleNoRedirects(), delegateQueue: nil)
    }
    private var key: String { "google:" + identity.ownerID.uuidString + ":" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    public func accounts() async throws -> [WorkspaceGoogleAccount] {
        try await credentials.read(key).map { try JSONDecoder().decode([WorkspaceGoogleAccount].self, from: $0) } ?? []
    }
    public func connect(plugin: WorkspaceGooglePlugin, authorization: GoogleOAuthAuthorization, callback: URL) async throws {
        try _Concurrency.Task.checkCancellation()
        guard !mutating, !suspended else { throw GoogleOAuthError.serviceUnavailable }; mutating = true; defer { mutating = false }
        let tokens = try await GoogleOAuthTokenClient(session: session).exchange(authorization: authorization, callback: callback)
        guard plugin.access.allSatisfy({ tokens.scopes.contains($0.scope) }) else { throw GoogleOAuthError.invalidScopes }
        let data = try await fetch(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!, token: tokens.accessToken)
        struct User: Decodable { let email: String; let email_verified: Bool }
        let user = try JSONDecoder().decode(User.self, from: data)
        guard user.email_verified, user.email.utf8.count <= 800, !suspended else { throw GoogleOAuthError.accessDenied }
        try await verify(plugin: plugin, token: tokens.accessToken)
        try _Concurrency.Task.checkCancellation()
        var values = try await accounts()
        let previousCredentials = try JSONEncoder().encode(values)
        let id = values.first { $0.plugin == plugin && $0.email == user.email }?.id ?? UUID()
        let account = WorkspaceGoogleAccount(id: id, plugin: plugin, email: user.email,
            configuration: .init(clientID: authorization.configuration.clientID, redirectURI: authorization.configuration.redirectURI, clientSecret: authorization.configuration.clientSecret), tokens: tokens)
        values.removeAll { $0.id == id }; values.append(account)
        // Persist the token before granting replicated access; a failed grant exposes no executable tool.
        try await credentials.write(JSONEncoder().encode(values), name: key)
        do {
            try _Concurrency.Task.checkCancellation()
            try await WorkspaceExternalAccess(repository: repository, identity: identity).save(id: id, plugin: plugin.rawValue, service: plugin.name,
                account: user.email, scopes: tokens.scopes.sorted())
        } catch {
            try? await credentials.write(previousCredentials, name: key)
            throw error
        }
    }
    public func disconnect(_ id: UUID) async throws {
        guard !mutating else { throw GoogleOAuthError.serviceUnavailable }; mutating = true; defer { mutating = false }
        var values = try await accounts(); guard values.contains(where: { $0.id == id }) else { throw GoogleOAuthError.accessDenied }
        // Access is removed even if the network cannot revoke the provider token.
        try await WorkspaceExternalAccess(repository: repository, identity: identity).disconnect(id)
        values.removeAll { $0.id == id }; try await credentials.write(JSONEncoder().encode(values), name: key)
    }
    public func stop() { suspended = true }
    public func resume() { suspended = false }
    public func verifyAccount(_ id: UUID) async throws {
        guard !suspended else { throw GoogleOAuthError.accessDenied }
        let account = try await fresh(id)
        try await verify(plugin: account.plugin, token: account.tokens.accessToken)
    }
    private func verify(plugin: WorkspaceGooglePlugin, token: String) async throws {
        let address: String
        switch plugin {
        case .gmail: address = "https://gmail.googleapis.com/gmail/v1/users/me/profile?fields=emailAddress"
        case .calendar: address = "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=1&fields=items(id)"
        case .drive: address = "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)"
        }
        _ = try await fetch(url: URL(string: address)!, token: token)
    }
    func upload(accountID: UUID, file: GoogleDriveUpload) async throws -> ChatJSON {
        guard !suspended else { throw GoogleOAuthError.accessDenied }
        let account = try await fresh(accountID)
        guard account.plugin == .drive, account.tokens.scopes.contains(GoogleAccess.driveFile.scope) else { throw GoogleOAuthError.invalidScopes }
        if let parent = file.parentID {
            let folder = try await request(accountID: accountID, path: ["drive", "v3", "files", parent],
                query: ["fields": "id,mimeType,trashed,capabilities(canAddChildren)"])
            guard folder.mcpFields["mimeType"] == .string("application/vnd.google-apps.folder"),
                  folder.mcpFields["trashed"] != .bool(true),
                  folder.mcpFields["capabilities"]?.mcpFields["canAddChildren"] == .bool(true) else { throw GoogleOAuthError.accessDenied }
        }
        let multipart = try file.multipart()
        let data = try await fetch(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,mimeType,size,webViewLink,parents")!,
            token: account.tokens.accessToken, method: "POST", rawBody: multipart.body, contentType: multipart.contentType)
        guard !suspended else { throw NativeExecutionError.unknown }
        let result = try JSONDecoder().decode(ChatJSON.self, from: data)
        guard let id = result.mcpFields["id"]?.mcpString,
              id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { throw GoogleOAuthError.serviceUnavailable }
        var fields = result.mcpFields
        fields["webViewLink"] = .string("https://drive.google.com/file/d/" + id + "/view")
        fields["state"] = .string("saved")
        return ChatJSON.object(fields).redactingSecrets([account.tokens.accessToken, account.tokens.refreshToken ?? ""])
    }
    func request(accountID: UUID, host: String = "www.googleapis.com", path: [String], query: [String: String] = [:], method: String = "GET", body: ChatJSON? = nil, text: Bool = false, etag: String? = nil) async throws -> ChatJSON {
        guard !suspended, ["www.googleapis.com", "gmail.googleapis.com"].contains(host), !path.isEmpty,
              path.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }), ["GET", "POST", "PATCH", "DELETE"].contains(method) else { throw GoogleOAuthError.accessDenied }
        let account = try await fresh(accountID)
        var url = URL(string: "https://" + host)!
        for segment in path { url.appendPathComponent(segment) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        let data = try await fetch(url: components.url!, token: account.tokens.accessToken, method: method, body: body, etag: etag)
        guard !suspended else { throw GoogleOAuthError.accessDenied }
        if data.isEmpty { return .object(["state": .string("completed")]) }
        let value = text ? ChatJSON.object(["content": .string(String(decoding: data.prefix(48_000), as: UTF8.self)), "truncated": .bool(data.count > 48_000)]) : try JSONDecoder().decode(ChatJSON.self, from: data)
        return value.redactingSecrets([account.tokens.accessToken, account.tokens.refreshToken ?? ""])
    }
    private func fresh(_ id: UUID) async throws -> WorkspaceGoogleAccount {
        var values = try await accounts()
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw GoogleOAuthError.accessDenied }
        var account = values[index]
        guard account.tokens.expiresAt <= Date().addingTimeInterval(60) else { return account }
        guard !mutating else { throw GoogleOAuthError.serviceUnavailable }; mutating = true; defer { mutating = false }
        let config = try GoogleOAuthConfiguration(clientID: account.configuration.clientID, redirectURI: account.configuration.redirectURI, clientSecret: account.configuration.clientSecret)
        account.tokens = try await GoogleOAuthTokenClient(session: session).refresh(configuration: config, previous: account.tokens)
        guard !suspended else { throw GoogleOAuthError.accessDenied }
        values[index] = account; try await credentials.write(JSONEncoder().encode(values), name: key)
        return account
    }
    private func fetch(url: URL, token: String, method: String = "GET", body: ChatJSON? = nil, etag: String? = nil, rawBody: Data? = nil, contentType: String? = nil) async throws -> Data {
        guard !token.isEmpty, !token.contains(where: { $0.isNewline || $0 == "\0" }) else { throw GoogleOAuthError.invalidTokenResponse }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let rawBody, let contentType { request.httpBody = rawBody; request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let etag {
            guard !etag.isEmpty, !etag.contains(where: { $0.isNewline || $0 == "\0" }) else { throw GoogleOAuthError.invalidConfiguration }
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleOAuthError.serviceUnavailable }
        if http.statusCode == 401 { throw GoogleOAuthError.authorizationExpired }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes { guard data.count < 65536 else { break }; data.append(byte) }
            let value = try? JSONDecoder().decode(ChatJSON.self, from: data)
            let error = value?.mcpFields["error"]?.mcpFields ?? [:]
            let details: [ChatJSON]
            if case .array(let items) = error["details"] { details = items } else { details = [] }
            let errors: [ChatJSON]
            if case .array(let items) = error["errors"] { errors = items } else { errors = [] }
            let reasons = Set((details + errors).compactMap { $0.mcpFields["reason"]?.mcpString })
            if !reasons.isDisjoint(with: ["SERVICE_DISABLED", "accessNotConfigured"]) { throw GoogleOAuthError.apiNotEnabled }
            if reasons.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") { throw GoogleOAuthError.invalidScopes }
            throw GoogleOAuthError.accessDenied
        }
        var data = Data()
        for try await byte in bytes { guard data.count < 2_000_000 else { throw GoogleOAuthError.serviceUnavailable }; data.append(byte) }
        return data
    }
}
private final class GoogleNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
