import CryptoKit
import Foundation
import Security

public struct MCPOAuthCredentials: Codable, Equatable, Sendable {
    public let resource: URL
    public let tokenEndpoint: URL
    public let clientID: String
    public let refreshToken: String?
    public let expiresAt: Date
}

public struct MCPOAuthAttempt: Sendable {
    public let url: URL
    public let resource: URL
    public let tokenEndpoint: URL
    public let clientID: String
    public let redirectURI: URL
    private let state: String
    private let verifier: String
    public init(authorizationEndpoint: URL, tokenEndpoint: URL, resource: URL, clientID: String, redirectURI: URL, scope: String) throws {
        self.resource = resource; self.tokenEndpoint = tokenEndpoint; self.clientID = clientID; self.redirectURI = redirectURI
        state = try Self.random(); verifier = try Self.random()
        guard authorizationEndpoint.scheme == "https", tokenEndpoint.scheme == "https", !clientID.isEmpty else { throw MCPError.configuration }
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "response_type", value: "code"), .init(name: "resource", value: resource.absoluteString), .init(name: "scope", value: scope),
            .init(name: "state", value: state), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: Self.base64(Data(SHA256.hash(data: Data(verifier.utf8)))))]
        guard let url = components.url else { throw MCPError.configuration }; self.url = url
    }
    public func tokenFields(callback: URL) throws -> [String: String] {
        guard callback.scheme == redirectURI.scheme, callback.host == redirectURI.host, callback.path == redirectURI.path,
              callback.fragment == nil, callback.user == nil, callback.password == nil, callback.port == nil,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw MCPError.configuration }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }), items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.utf8.count <= 8192 else { throw MCPError.denied }
        return ["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "client_id": clientID,
                "redirect_uri": redirectURI.absoluteString, "resource": resource.absoluteString]
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw MCPError.unavailable }
        return base64(Data(bytes))
    }
    private static func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

/// OAuth metadata and tokens use a cookie-free, no-redirect session. Tokens are never sent to discovery URLs.
public actor MCPOAuthClient {
    /// A protected resource can cover child endpoints, but cannot change origin or path boundary.
    public nonisolated static func matches(resource: URL, endpoint: String) -> Bool {
        guard let target = URL(string: endpoint), resource.scheme == "https", target.scheme == resource.scheme,
              target.host == resource.host, target.port == resource.port, resource.user == nil, resource.password == nil,
              resource.query == nil, resource.fragment == nil else { return false }
        let path = resource.path.hasSuffix("/") ? String(resource.path.dropLast()) : resource.path
        return target.path == path || target.path.hasPrefix(path + "/")
    }
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: MCPOAuthNoRedirects(), delegateQueue: nil)
    }
    public func begin(endpoint: String, redirectURI: URL, clientID: String? = nil) async throws -> MCPOAuthAttempt {
        guard let resource = URL(string: endpoint), resource.scheme == "https", resource.user == nil, resource.password == nil, resource.fragment == nil, resource.query == nil else { throw MCPError.configuration }
        var origin = URLComponents(url: resource, resolvingAgainstBaseURL: false)!
        origin.path = ""; origin.query = nil
        guard let base = origin.url else { throw MCPError.configuration }
        var resourceCandidates: [URL] = []
        let (_, challenge) = try await fetch(URLRequest(url: resource), acceptFailure: true)
        let header = challenge.value(forHTTPHeaderField: "WWW-Authenticate") ?? ""
        func parameter(_ name: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "(?:^|[, \\t])" + name + "=\"([^\"]+)\"", options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)), let range = Range(match.range(at: 1), in: header) else { return nil }
            return String(header[range])
        }
        if let raw = parameter("resource_metadata"), let url = URL(string: raw), url.scheme == "https" { resourceCandidates.append(url) }
        resourceCandidates += [base.appendingPathComponent(".well-known/oauth-protected-resource" + resource.path), base.appendingPathComponent(".well-known/oauth-protected-resource")]
        let protected = try await firstMetadata(resourceCandidates)
        guard let advertised = protected["resource"] as? String, let canonicalResource = URL(string: advertised),
              Self.matches(resource: canonicalResource, endpoint: endpoint) else { throw MCPError.configuration }
        guard let issuers = protected["authorization_servers"] as? [String], let rawIssuer = issuers.first,
              let issuer = URL(string: rawIssuer), issuer.scheme == "https", issuer.user == nil, issuer.password == nil,
              issuer.query == nil, issuer.fragment == nil else { throw MCPError.configuration }
        var issuerOrigin = URLComponents(url: issuer, resolvingAgainstBaseURL: false)!; issuerOrigin.path = ""
        let issuerBase = issuerOrigin.url!
        let metadata = try await firstMetadata([
            issuerBase.appendingPathComponent(".well-known/oauth-authorization-server" + issuer.path),
            issuerBase.appendingPathComponent(".well-known/openid-configuration" + issuer.path),
            issuer.appendingPathComponent(".well-known/openid-configuration")])
        guard metadata["issuer"] as? String == issuer.absoluteString,
              let authRaw = metadata["authorization_endpoint"] as? String, let auth = URL(string: authRaw), auth.scheme == "https",
              let tokenRaw = metadata["token_endpoint"] as? String, let token = URL(string: tokenRaw), token.scheme == "https",
              (metadata["code_challenge_methods_supported"] as? [String])?.contains("S256") == true else { throw MCPError.configuration }
        let registered: String
        if let clientID, !clientID.isEmpty { registered = clientID }
        else {
            guard let raw = metadata["registration_endpoint"] as? String, let registration = URL(string: raw), registration.scheme == "https" else { throw MCPError.configuration }
            var request = URLRequest(url: registration); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["client_name": "Blot", "redirect_uris": [redirectURI.absoluteString],
                "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"], "token_endpoint_auth_method": "none"])
            let (data, _) = try await fetch(request)
            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = response["client_id"] as? String,
                  !id.isEmpty, (response["token_endpoint_auth_method"] as? String ?? "none") == "none" else { throw MCPError.configuration }
            registered = id
        }
        let scope = parameter("scope") ?? (protected["scopes_supported"] as? [String] ?? []).joined(separator: " ")
        return try MCPOAuthAttempt(authorizationEndpoint: auth, tokenEndpoint: token, resource: canonicalResource, clientID: registered, redirectURI: redirectURI, scope: scope)
    }
    public func finish(_ attempt: MCPOAuthAttempt, callback: URL) async throws -> (String, MCPOAuthCredentials) {
        try await tokens(endpoint: attempt.tokenEndpoint, fields: attempt.tokenFields(callback: callback), resource: attempt.resource, clientID: attempt.clientID, previousRefresh: nil)
    }
    public func refresh(_ credentials: MCPOAuthCredentials) async throws -> (String, MCPOAuthCredentials) {
        guard let token = credentials.refreshToken, !token.isEmpty else { throw MCPError.http(401) }
        return try await tokens(endpoint: credentials.tokenEndpoint, fields: ["grant_type": "refresh_token", "refresh_token": token,
            "client_id": credentials.clientID, "resource": credentials.resource.absoluteString], resource: credentials.resource,
            clientID: credentials.clientID, previousRefresh: token)
    }
    private func tokens(endpoint: URL, fields: [String: String], resource: URL, clientID: String, previousRefresh: String?) async throws -> (String, MCPOAuthCredentials) {
        guard endpoint.scheme == "https", endpoint.user == nil, endpoint.password == nil else { throw MCPError.configuration }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { key, value in
            (key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").utf8)
        let (data, _) = try await fetch(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let access = json["access_token"] as? String,
              !access.isEmpty, access.utf8.count <= 8192, !access.contains(where: { $0.isNewline }),
              (json["token_type"] as? String)?.lowercased() == "bearer" else { throw MCPError.protocolViolation }
        let seconds = json["expires_in"] as? Double
        guard json["expires_in"] == nil || (seconds.map { $0.isFinite && $0 > 0 && $0 <= 31_536_000 } ?? false) else { throw MCPError.protocolViolation }
        let credentials = MCPOAuthCredentials(resource: resource, tokenEndpoint: endpoint, clientID: clientID,
            refreshToken: json["refresh_token"] as? String ?? previousRefresh, expiresAt: seconds.map { Date().addingTimeInterval($0) } ?? .distantFuture)
        return (access, credentials)
    }
    private func firstMetadata(_ urls: [URL]) async throws -> [String: Any] {
        for url in urls {
            do {
                let (data, _) = try await fetch(URLRequest(url: url))
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] { return json }
            } catch is CancellationError { throw CancellationError() } catch {}
        }
        throw MCPError.configuration
    }
    private func fetch(_ request: URLRequest, acceptFailure: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil else { throw MCPError.configuration }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, acceptFailure || (200...299).contains(response.statusCode) else { throw MCPError.configuration }
        var data = Data()
        for try await byte in bytes { guard data.count < 256_000 else { throw MCPError.responseTooLarge }; data.append(byte) }
        return (data, response)
    }
}

private final class MCPOAuthNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
