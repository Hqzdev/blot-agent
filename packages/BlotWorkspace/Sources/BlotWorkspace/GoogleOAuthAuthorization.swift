import CryptoKit
import Foundation
import Security

/// A single browser attempt. Keep it only in memory; never replicate verifier, code or tokens.
public struct GoogleOAuthAuthorization: Sendable {
    public let url: URL
    public let configuration: GoogleOAuthConfiguration
    private let state: String
    private let verifier: String

    public init(configuration: GoogleOAuthConfiguration, access: Set<GoogleAccess>) throws {
        guard !access.isEmpty else { throw GoogleOAuthError.invalidScopes }
        self.configuration = configuration
        self.state = try Self.random()
        self.verifier = try Self.random()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: configuration.clientID),
            .init(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: (["openid", "email"] + access.map(\.scope)).sorted().joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account"),
        ]
        self.url = components.url!
    }

    public func tokenRequest(callback: URL) throws -> URLRequest {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.scheme == configuration.redirectURI.scheme,
              components.host == nil, components.path == configuration.redirectURI.path,
              components.fragment == nil else { throw GoogleOAuthError.invalidCallback }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state else { throw GoogleOAuthError.invalidCallback }
        if items.contains(where: { $0.name == "error" }) { throw GoogleOAuthError.accessDenied }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.utf8.count <= 8192 else { throw GoogleOAuthError.invalidCallback }
        return GoogleOAuthTokenClient.request([
            "client_id": configuration.clientID, "redirect_uri": configuration.redirectURI.absoluteString,
            "code": code, "code_verifier": verifier, "grant_type": "authorization_code",
        ])
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw GoogleOAuthError.serviceUnavailable
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
