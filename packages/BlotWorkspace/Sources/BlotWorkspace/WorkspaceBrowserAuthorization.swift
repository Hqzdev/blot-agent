import CryptoKit
import Foundation
import Security

public struct WorkspaceBrowserTokenExchange: Encodable, Sendable {
    public let code: String
    public let codeVerifier: String
    public let clientID: String
    public let redirectURI: String
}

/// A single system-browser sign-in attempt. A callback carries a short-lived code, never session tokens.
public struct WorkspaceBrowserAuthorization: Sendable {
    public let url: URL
    public let callbackURL: URL
    private let state: String
    private let verifier: String
    private let clientID: String
    public init(loginURL: URL, platform: String, registering: Bool = false) throws {
        guard loginURL.scheme == "https", loginURL.host != nil, loginURL.user == nil, loginURL.password == nil,
              loginURL.fragment == nil, loginURL.query == nil, ["macos", "ios"].contains(platform) else {
            throw WorkspaceCloudError.invalidConfiguration
        }
        clientID = "blot-" + platform
        callbackURL = URL(string: "blot-agent-" + platform + ":/oauth/account")!
        state = try Self.random(); verifier = try Self.random()
        var components = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: callbackURL.absoluteString), .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "intent", value: registering ? "register" : "login")]
        url = components.url!
    }
    public func exchange(callback: URL) throws -> WorkspaceBrowserTokenExchange {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.scheme == callbackURL.scheme, components.host == nil, components.path == callbackURL.path,
              components.fragment == nil, components.user == nil, components.password == nil else { throw WorkspaceCloudError.authenticationRequired }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count == 1, let code = items.first(where: { $0.name == "code" })?.value,
              code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              !items.contains(where: { $0.name == "error" || $0.name == "access_token" || $0.name == "refresh_token" }) else {
            throw WorkspaceCloudError.authenticationRequired
        }
        return .init(code: code, codeVerifier: verifier, clientID: clientID, redirectURI: callbackURL.absoluteString)
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw WorkspaceCloudError.invalidConfiguration }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
