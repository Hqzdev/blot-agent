import Foundation

public struct WorkspaceCloudTokens: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: String
    public let ownerID: UUID
    public let workspaceID: UUID
    public let deviceID: UUID?
    public let bootstrapAllowed: Bool?
}

/// Refresh is single-flight, so rotating refresh tokens cannot race on one device.
public actor WorkspaceCloudSession: WorkspaceCloudAuthorization {
    private let http: WorkspaceCloudHTTP
    private let credentials: any WorkspaceCredentialStore
    private let credentialName: String
    private let persistence: WorkspaceCredentialPersistence
    private var mayRestore = true
    private var tokens: WorkspaceCloudTokens?
    private var refresh: Task<WorkspaceCloudTokens, Error>?
    private var generation: UInt64 = 0

    public init(http: WorkspaceCloudHTTP, credentials: any WorkspaceCredentialStore, credentialName: String) {
        self.http = http; self.credentials = credentials; self.credentialName = credentialName
        self.persistence = WorkspaceCredentialPersistence(store: credentials, name: credentialName)
    }
    public func restore() async throws -> WorkspaceCloudTokens? {
        guard mayRestore else { return nil }
        let expected = generation
        guard let data = try await credentials.read(credentialName) else { return nil }
        guard generation == expected, mayRestore else { throw WorkspaceCloudError.authenticationRequired }
        let saved = try JSONDecoder().decode(WorkspaceCloudTokens.self, from: data)
        tokens = saved
        _ = try await accessToken()
        return tokens
    }
    public func exchange(authorization: WorkspaceBrowserAuthorization, callback: URL) async throws -> WorkspaceCloudTokens {
        let input = try authorization.exchange(callback: callback)
        let expected = beginAuthentication()
        try await persistence.replace(with: nil)
        guard generation == expected else { throw WorkspaceCloudError.authenticationRequired }
        let result = try await http.request(WorkspaceCloudTokens.self, method: "POST", path: ["v1", "auth", "browser", "token"],
            body: JSONEncoder().encode(input))
        try await saveNew(result, expected: expected)
        return result
    }
    public func register(email: String, password: String, name: String) async throws {
        struct Input: Encodable { let email: String; let password: String; let name: String }
        try await http.empty(method: "POST", path: ["v1", "auth", "register"], body: JSONEncoder().encode(Input(email: email, password: password, name: name)))
    }
    public func verify(email: String, code: String) async throws -> WorkspaceCloudTokens {
        let expected = beginAuthentication()
        try await persistence.replace(with: nil)
        guard generation == expected else { throw WorkspaceCloudError.authenticationRequired }
        struct Input: Encodable { let email: String; let code: String }
        let result = try await http.request(WorkspaceCloudTokens.self, method: "POST", path: ["v1", "auth", "verify"], body: JSONEncoder().encode(Input(email: email, code: code)))
        try await saveNew(result, expected: expected)
        return result
    }
    public func login(email: String, password: String) async throws -> WorkspaceCloudTokens {
        let expected = beginAuthentication()
        try await persistence.replace(with: nil)
        guard generation == expected else { throw WorkspaceCloudError.authenticationRequired }
        struct Input: Encodable { let email: String; let password: String }
        let result = try await http.request(WorkspaceCloudTokens.self, method: "POST", path: ["v1", "auth", "login"], body: JSONEncoder().encode(Input(email: email, password: password)))
        try await saveNew(result, expected: expected)
        return result
    }
    public func requestPasswordReset(email: String) async throws {
        struct Input: Encodable { let email: String }
        try await http.empty(method: "POST", path: ["v1", "auth", "password", "request"], body: JSONEncoder().encode(Input(email: email)))
    }
    public func resetPassword(email: String, code: String, password: String) async throws {
        struct Input: Encodable { let email: String; let code: String; let password: String }
        try await http.empty(method: "POST", path: ["v1", "auth", "password", "reset"], body: JSONEncoder().encode(Input(email: email, code: code, password: password)))
        try await forget()
    }
    public func logout() async throws {
        let previous = tokens
        try await forget()
        guard let previous else { return }
        do {
            try await http.empty(method: "POST", path: ["v1", "auth", "logout"], accessToken: previous.accessToken)
        } catch WorkspaceCloudError.rejected(status: 401, code: _) {
            // Refresh only to revoke an expired session. Never restore its credentials locally.
            struct Input: Encodable { let refreshToken: String }
            let renewed = try await http.request(WorkspaceCloudTokens.self, method: "POST", path: ["v1", "auth", "refresh"],
                body: JSONEncoder().encode(Input(refreshToken: previous.refreshToken)))
            guard renewed.sessionID == previous.sessionID, renewed.ownerID == previous.ownerID,
                  renewed.workspaceID == previous.workspaceID else { throw WorkspaceCloudError.invalidResponse }
            try await http.empty(method: "POST", path: ["v1", "auth", "logout"], accessToken: renewed.accessToken)
        }
    }
    public func forget() async throws {
        generation &+= 1
        mayRestore = false
        refresh?.cancel(); refresh = nil; tokens = nil
        try await persistence.replace(with: nil)
    }
    public func current() -> WorkspaceCloudTokens? { tokens }
    public func accessToken() async throws -> String {
        try await token(forceRefresh: false)
    }
    public func refreshDeviceBinding() async throws -> WorkspaceCloudTokens? {
        _ = try await token(forceRefresh: true)
        return tokens
    }
    private func token(forceRefresh: Bool) async throws -> String {
        guard let current = tokens else { throw WorkspaceCloudError.authenticationRequired }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if !forceRefresh, let expiry = fractional.date(from: current.expiresAt) ?? ISO8601DateFormatter().date(from: current.expiresAt),
           expiry.timeIntervalSinceNow > 60 { return current.accessToken }
        let expected = generation
        let worker: Task<WorkspaceCloudTokens, Error>
        if let refresh { worker = refresh }
        else {
            let http = self.http
            worker = Task {
                struct Input: Encodable { let refreshToken: String }
                return try await http.request(WorkspaceCloudTokens.self, method: "POST", path: ["v1", "auth", "refresh"], body: JSONEncoder().encode(Input(refreshToken: current.refreshToken)))
            }
            refresh = worker
        }
        do {
            let result = try await worker.value
            guard generation == expected, tokens?.sessionID == result.sessionID,
                  result.ownerID == current.ownerID, result.workspaceID == current.workspaceID else { throw WorkspaceCloudError.authenticationRequired }
            try await persistence.replace(with: JSONEncoder().encode(result))
            guard generation == expected else { throw WorkspaceCloudError.authenticationRequired }
            tokens = result; refresh = nil
            return result.accessToken
        } catch {
            if generation == expected { refresh = nil }
            throw error
        }
    }
    private func beginAuthentication() -> UInt64 {
        generation &+= 1
        mayRestore = false
        refresh?.cancel(); refresh = nil; tokens = nil
        return generation
    }
    private func saveNew(_ value: WorkspaceCloudTokens, expected: UInt64) async throws {
        guard generation == expected else { throw WorkspaceCloudError.authenticationRequired }
        try await persistence.replace(with: JSONEncoder().encode(value))
        guard generation == expected else { throw WorkspaceCloudError.authenticationRequired }
        tokens = value; mayRestore = true
    }
}
