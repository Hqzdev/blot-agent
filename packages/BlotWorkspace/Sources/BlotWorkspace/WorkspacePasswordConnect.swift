import Foundation

public struct WorkspacePasswordEntry: Identifiable, Decodable, Sendable {
    public let id: String
    public let title: String
    public let category: String
}
public struct WorkspacePasswordVault: Identifiable, Decodable, Sendable { public let id: String; public let name: String }

/// 1Password Connect credentials and selected vaults stay in the device Keychain.
public actor WorkspacePasswordConnect {
    private struct Configuration: Codable { let endpoint: URL; let token: String; let vaults: Set<String> }
    private let credentials: any WorkspaceCredentialStore
    private let key: String
    private let session: URLSession
    public init(credentials: any WorkspaceCredentialStore, ownerID: UUID) {
        self.credentials = credentials; key = "password-connect:" + ownerID.uuidString
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil; config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: PasswordNoRedirects(), delegateQueue: nil)
    }
    public func inspect(endpoint: String, token: String) async throws -> [WorkspacePasswordVault] {
        let config = try Self.configuration(endpoint: endpoint, token: token, vaults: [])
        return try JSONDecoder().decode([WorkspacePasswordVault].self, from: await fetch(config, path: ["v1", "vaults"]))
    }
    public func save(endpoint: String, token: String, vaults: Set<String>) async throws {
        guard !vaults.isEmpty else { throw WorkspaceStorageError.invalidParameters }
        let available = try await inspect(endpoint: endpoint, token: token)
        guard vaults.isSubset(of: Set(available.map(\.id))) else { throw WorkspaceStorageError.permissionDenied }
        try await credentials.write(JSONEncoder().encode(Self.configuration(endpoint: endpoint, token: token, vaults: vaults)), name: key)
    }
    public func vaults() async throws -> [WorkspacePasswordVault] {
        let config = try await configuration()
        return try JSONDecoder().decode([WorkspacePasswordVault].self, from: await fetch(config, path: ["v1", "vaults"])).filter { config.vaults.contains($0.id) }
    }
    public func entries(vaultID: String) async throws -> [WorkspacePasswordEntry] {
        let config = try await configuration()
        guard config.vaults.contains(vaultID) else { throw WorkspaceStorageError.permissionDenied }
        return try JSONDecoder().decode([WorkspacePasswordEntry].self, from: await fetch(config, path: ["v1", "vaults", vaultID, "items"])).filter { $0.category == "LOGIN" }
    }
    /// The owner chooses the entry in native UI; secrets never enter a model response.
    public func importLogin(vaultID: String, itemID: String, into vault: WorkspaceVaultService) async throws {
        let config = try await configuration()
        guard config.vaults.contains(vaultID) else { throw WorkspaceStorageError.permissionDenied }
        struct Item: Decodable {
            struct Field: Decodable { let purpose: String?; let value: String? }
            struct Address: Decodable { let href: String; let primary: Bool? }
            let title: String; let category: String; let fields: [Field]; let urls: [Address]?
        }
        let item = try JSONDecoder().decode(Item.self, from: await fetch(config, path: ["v1", "vaults", vaultID, "items", itemID]))
        guard item.category == "LOGIN", let url = item.urls?.first(where: { $0.primary == true })?.href ?? item.urls?.first?.href,
              let username = item.fields.first(where: { $0.purpose == "USERNAME" })?.value,
              let password = item.fields.first(where: { $0.purpose == "PASSWORD" })?.value else { throw WorkspaceStorageError.invalidParameters }
        let entry = WorkspaceVaultItem(title: item.title, kind: .login, fields: ["url": url, "username": username, "password": password])
        _ = try await vault.importLogins([entry])
    }
    public func disconnect() async throws { try await credentials.remove(key) }
    public func connected() async throws -> Bool { try await credentials.read(key) != nil }
    private func configuration() async throws -> Configuration {
        guard let data = try await credentials.read(key) else { throw WorkspaceStorageError.permissionDenied }
        return try JSONDecoder().decode(Configuration.self, from: data)
    }
    private static func configuration(endpoint: String, token: String, vaults: Set<String>) throws -> Configuration {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !token.isEmpty, token.utf8.count <= 16_384, !token.contains(where: { $0.isNewline || $0 == "\0" }), vaults.count <= 100 else { throw WorkspaceStorageError.invalidParameters }
        return .init(endpoint: url, token: token, vaults: vaults)
    }
    private func fetch(_ config: Configuration, path: [String]) async throws -> Data {
        guard path.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }) else { throw WorkspaceStorageError.invalidParameters }
        var url = config.endpoint; for segment in path { url.appendPathComponent(segment) }
        var request = URLRequest(url: url); request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw WorkspaceStorageError.permissionDenied }
        var data = Data(); for try await byte in bytes { guard data.count < 2_000_000 else { throw WorkspaceStorageError.invalidRecord }; data.append(byte) }
        return data
    }
}
private final class PasswordNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
