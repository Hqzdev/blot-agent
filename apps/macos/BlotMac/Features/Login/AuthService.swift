import BlotDesign
import Foundation
import BlotAPI

struct AuthUser: Equatable {
    var accountID: UUID? = nil
    var email: String
    var name: String
    var installedPlugins: [AccountPlugin] = []
    var profileStatistics: ProfileStatistics?

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        let value = String(letters).uppercased()
        return value.isEmpty ? String(email.prefix(2)).uppercased() : value
    }
}


enum AuthError: LocalizedError, Equatable {
    case invalidEmail, emptyPassword, wrongCredentials, invalidCode, codeExpired
    var errorDescription: String? {
        switch self {
        case .invalidEmail: "Enter a valid email address."
        case .emptyPassword: "Enter a password of at least 12 characters."
        case .wrongCredentials: "Wrong email or password."
        case .invalidCode: "That code is not right."
        case .codeExpired: "The code has expired. Request a new one."
        }
    }
}

@MainActor
protocol AuthService {
    func register(email: String, password: String) async throws
    func logIn(email: String, password: String, remember: Bool) async throws -> AuthUser
    func sendCode(to email: String) async throws
    func verify(code: String, email: String) async throws
    func requestReset(email: String) async throws
    func reset(email: String, code: String, password: String) async throws
}

@MainActor
struct LiveAuthService: AuthService {
    private nonisolated struct Credentials: Encodable, Sendable { let email: String; let password: String; var name: String? = nil; var remember = true }
    private nonisolated struct Verify: Encodable, Sendable { let email: String; let code: String }
    private nonisolated struct Reset: Encodable, Sendable { let email: String; let code: String; let password: String }
    private nonisolated struct Account: Decodable, Sendable { let id: UUID; let email: String; let displayName: String; let verified: Bool }
    private nonisolated struct Token: Decodable, Sendable { let token: String; let expiresAt: String }
    private nonisolated struct Login: Decodable, Sendable { let session: Token; let account: Account }
    private func client() async throws -> BackendClient { try await BackendRuntime.shared.start(); return BackendRuntime.shared.client }
    func register(email: String, password: String) async throws {
        let client = try await client()
        let _: Account = try await client.post("v2/auth/register", body: Credentials(email: email, password: password), as: Account.self)
    }
    func logIn(email: String, password: String, remember: Bool) async throws -> AuthUser {
        let client = try await client()
        let result = try await client.post("v2/auth/login", body: Credentials(email: email, password: password, remember: remember), as: Login.self)
        if remember { try BackendKeychain.write(result.session.token, key: "session") } else { try BackendKeychain.remove("session") }
        await client.useToken(result.session.token)
        return AuthUser(accountID: result.account.id, email: result.account.email, name: result.account.displayName)
    }
    func sendCode(to email: String) async throws {
        let client = try await client()
        let _: [String: Bool] = try await client.post("v2/auth/resend", body: Verify(email: email, code: ""), as: [String: Bool].self)
    }
    func verify(code: String, email: String) async throws {
        let client = try await client()
        let _: Account = try await client.post("v2/auth/verify", body: Verify(email: email, code: code), as: Account.self)
    }
    func requestReset(email: String) async throws {
        let client = try await client()
        let _: [String: Bool] = try await client.post("v2/auth/password/request", body: Verify(email: email, code: ""), as: [String: Bool].self)
    }
    func reset(email: String, code: String, password: String) async throws {
        let client = try await client()
        let _: [String: Bool] = try await client.post("v2/auth/password/reset", body: Reset(email: email, code: code, password: password), as: [String: Bool].self)
    }
    func restore() async throws -> AuthUser? {
        guard let token = try BackendKeychain.read("session") else { return nil }
        let client = try await client()
        await client.useToken(token)
        let result = try await client.get("v2/auth/me", as: Account.self)
        return AuthUser(accountID: result.id, email: result.email, name: result.displayName)
    }
}

/// В UserDefaults остаётся только подсказка формы. Доступ подтверждает backend.
@MainActor
enum SessionStore {
    static var lastEmail: String { UserDefaults.standard.string(forKey: "blot.lastEmail") ?? "" }
    static func rememberEmail(_ email: String) { UserDefaults.standard.set(email, forKey: "blot.lastEmail") }
    static func save(_ user: AuthUser) { rememberEmail(user.email) }
    static func clear() { try? BackendKeychain.remove("session") }
}
