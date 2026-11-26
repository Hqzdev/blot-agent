import BlotDomain
import Foundation

public enum WorkspaceMessagingProvider: String, Codable, Sendable, CaseIterable {
    case slack, teams
    public var name: String { self == .slack ? "Slack" : "Microsoft Teams" }
    var scopes: String { self == .slack ? "channels:read,groups:read,channels:history,groups:history,chat:write,search:read,users:read" : "offline_access User.Read Team.ReadBasic.All Channel.ReadBasic.All ChannelMessage.Read.All ChannelMessage.Send" }
    var tokenEndpoint: URL { URL(string: self == .slack ? "https://slack.com/api/oauth.v2.access" : "https://login.microsoftonline.com/organizations/oauth2/v2.0/token")! }
}
public struct WorkspaceMessagingAuthorization: Sendable {
    public let provider: WorkspaceMessagingProvider
    public let url: URL
    public let redirectURI: URL
    let attempt: MCPOAuthAttempt
    public init(provider: WorkspaceMessagingProvider, clientID: String, redirectURI: URL) throws {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, clientID.utf8.count <= 800 else { throw MCPError.configuration }
        self.provider = provider; self.redirectURI = redirectURI
        attempt = try MCPOAuthAttempt(authorizationEndpoint: URL(string: provider == .slack ? "https://slack.com/oauth/v2/authorize" : "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize")!, tokenEndpoint: provider.tokenEndpoint, resource: URL(string: provider == .slack ? "https://slack.com/api" : "https://graph.microsoft.com")!, clientID: clientID, redirectURI: redirectURI, scope: provider.scopes)
        var components = URLComponents(url: attempt.url, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems?.filter { $0.name != "resource" }.map { item in
            provider == .slack && item.name == "scope" ? URLQueryItem(name: "user_scope", value: item.value) : item
        }
        url = components.url!
    }
    func fields(_ callback: URL) throws -> [String: String] { var fields = try attempt.tokenFields(callback: callback); fields.removeValue(forKey: "resource"); if provider == .teams { fields["scope"] = provider.scopes }; return fields }
}
public struct WorkspaceMessagingAccount: Codable, Sendable, Identifiable {
    public let id: UUID; public let provider: WorkspaceMessagingProvider; public let name: String; public let workspace: String; public let userID: String
    let clientID: String?; var token: String; var refresh: String?; var expiresAt: Date
}

public actor WorkspaceMessagingService {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let credentials: any WorkspaceCredentialStore
    private let session: URLSession
    private var mutating = false
    private var suspended = false
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore) {
        self.repository = repository; self.identity = identity; self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config, delegate: MessagingNoRedirects(), delegateQueue: nil)
    }
    private var key: String { "messaging:" + identity.ownerID.uuidString + ":" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    public func accounts() async throws -> [WorkspaceMessagingAccount] { try await credentials.read(key).map { try JSONDecoder().decode([WorkspaceMessagingAccount].self, from: $0) } ?? [] }
    public func connect(_ authorization: WorkspaceMessagingAuthorization, callback: URL) async throws {
        guard !mutating, !suspended else { throw MCPError.accessChanged }; mutating = true; defer { mutating = false }
        let token = try await exchange(authorization.provider, fields: authorization.fields(callback))
        try await save(provider: authorization.provider, clientID: authorization.attempt.clientID, token: token)
    }
    public func connectSlackBot(_ token: String) async throws {
        guard !mutating, !suspended, token.hasPrefix("xoxb-") else { throw MCPError.configuration }; mutating = true; defer { mutating = false }
        try await save(provider: .slack, clientID: nil, token: (token, nil, .distantFuture))
    }
    private func save(provider: WorkspaceMessagingProvider, clientID: String?, token: (String, String?, Date)) async throws {
        let profile = try await api(provider: provider, token: token.0, path: provider == .slack ? ["auth.test"] : ["me"])
        let fields = profile.mcpFields
        let user = fields[provider == .slack ? "user_id" : "id"]?.mcpString ?? ""
        let workspace = provider == .slack ? fields["team_id"]?.mcpString ?? "" : "organizations"
        let name = fields[provider == .slack ? "team" : "userPrincipalName"]?.mcpString ?? provider.name
        guard !user.isEmpty, !workspace.isEmpty, !suspended else { throw MCPError.configuration }
        var accounts = try await accounts()
        let previousCredentials = try JSONEncoder().encode(accounts)
        let id = accounts.first { $0.provider == provider && $0.workspace == workspace && $0.userID == user }?.id ?? UUID()
        let account = WorkspaceMessagingAccount(id: id, provider: provider, name: name, workspace: workspace, userID: user, clientID: clientID, token: token.0, refresh: token.1, expiresAt: token.2)
        accounts.removeAll { $0.id == id }; accounts.append(account)
        try await credentials.write(JSONEncoder().encode(accounts), name: key)
        do {
            try await WorkspaceExternalAccess(repository: repository, identity: identity).save(id: id, plugin: provider.rawValue, service: provider.name, account: name,
                scopes: provider.scopes.components(separatedBy: provider == .slack ? "," : " "))
        } catch {
            try? await credentials.write(previousCredentials, name: key)
            throw error
        }
    }
    public func disconnect(_ id: UUID) async throws {
        guard !mutating else { throw MCPError.accessChanged }; mutating = true; defer { mutating = false }
        var accounts = try await accounts(); try await WorkspaceExternalAccess(repository: repository, identity: identity).disconnect(id)
        accounts.removeAll { $0.id == id }; try await credentials.write(JSONEncoder().encode(accounts), name: key)
    }
    public func stop() { suspended = true }
    public func resume() { suspended = false }
    public func request(accountID: UUID, path: [String], query: [String: String] = [:], body: ChatJSON? = nil) async throws -> ChatJSON {
        guard !suspended else { throw MCPError.unavailable }
        let account = try await fresh(accountID)
        let value = try await api(provider: account.provider, token: account.token, path: path, query: query, body: body)
        guard !suspended else { throw MCPError.unavailable }
        return value.redactingSecrets([account.token, account.refresh ?? ""])
    }
    public func nextPage(accountID: UUID, path: [String], link: String) async throws -> ChatJSON {
        guard let account = try await accounts().first(where: { $0.id == accountID }), account.provider == .teams,
              let url = URL(string: link), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.scheme == "https", url.host == "graph.microsoft.com", url.port == nil, url.user == nil, url.password == nil, url.fragment == nil else { throw MCPError.denied }
        var expected = URL(string: "https://graph.microsoft.com/v1.0")!; for part in path { expected.appendPathComponent(part) }
        let items = components.queryItems ?? []
        guard url.path == expected.path, items.count <= 20, Set(items.map(\.name)).count == items.count else { throw MCPError.denied }
        return try await request(accountID: accountID, path: path, query: Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }))
    }
    private func fresh(_ id: UUID) async throws -> WorkspaceMessagingAccount {
        var values = try await accounts()
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw MCPError.denied }
        var account = values[index]
        guard account.expiresAt < Date().addingTimeInterval(60) else { return account }
        guard !mutating, let refresh = account.refresh, let clientID = account.clientID else { throw MCPError.denied }
        mutating = true; defer { mutating = false }
        var fields = ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID]
        if account.provider == .teams { fields["scope"] = account.provider.scopes }
        let result = try await exchange(account.provider, fields: fields)
        account.token = result.0; account.refresh = result.1 ?? refresh; account.expiresAt = result.2
        guard !suspended else { throw MCPError.unavailable }
        values[index] = account; try await credentials.write(JSONEncoder().encode(values), name: key); return account
    }
    private func exchange(_ provider: WorkspaceMessagingProvider, fields: [String: String]) async throws -> (String, String?, Date) {
        var request = URLRequest(url: provider.tokenEndpoint); request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
        let value = try await fetch(request), root = value.mcpFields
        if provider == .slack, root["ok"] != .bool(true) { throw MCPError.denied }
        let token = provider == .slack && root["authed_user"] != nil ? root["authed_user"]!.mcpFields : root
        guard let access = token["access_token"]?.mcpString, !access.isEmpty, access.utf8.count <= 16_384, !access.contains(where: { $0.isNewline }) else { throw MCPError.protocolViolation }
        let expires: Date
        if case .number(let seconds) = token["expires_in"], seconds.isFinite, seconds > 0, seconds <= 31_536_000 { expires = Date().addingTimeInterval(seconds) }
        else if token["expires_in"] == nil { expires = .distantFuture }
        else { throw MCPError.protocolViolation }
        return (access, token["refresh_token"]?.mcpString, expires)
    }
    private func api(provider: WorkspaceMessagingProvider, token: String, path: [String], query: [String: String] = [:], body: ChatJSON? = nil) async throws -> ChatJSON {
        guard !token.isEmpty, !token.contains(where: { $0.isNewline || $0 == "\0" }), path.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }) else { throw MCPError.configuration }
        var url = URL(string: provider == .slack ? "https://slack.com/api" : "https://graph.microsoft.com/v1.0")!
        for part in path { url.appendPathComponent(part) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!); request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        let value = try await fetch(request)
        guard provider != .slack || value.mcpFields["ok"] == .bool(true) else { throw MCPError.denied }
        return value
    }
    private func fetch(_ request: URLRequest) async throws -> ChatJSON {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw MCPError.denied }
        var data = Data(); for try await byte in bytes { guard data.count < 2_000_000 else { throw MCPError.responseTooLarge }; data.append(byte) }
        return try JSONDecoder().decode(ChatJSON.self, from: data)
    }
}
private final class MessagingNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
