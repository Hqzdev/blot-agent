import Foundation

/// Device-local credentials. This type is deliberately not a workspace record.
public struct GoogleOAuthTokens: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let scopes: Set<String>
}

public actor GoogleOAuthTokenClient {
    private struct Response: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let scope: String?
        let token_type: String
    }
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func exchange(authorization: GoogleOAuthAuthorization, callback: URL) async throws -> GoogleOAuthTokens {
        try await perform(authorization.tokenRequest(callback: callback), previous: nil)
    }

    public func refresh(configuration: GoogleOAuthConfiguration, previous: GoogleOAuthTokens) async throws -> GoogleOAuthTokens {
        guard let refresh = previous.refreshToken, !refresh.isEmpty else { throw GoogleOAuthError.authorizationExpired }
        return try await perform(Self.request([
            "client_id": configuration.clientID, "refresh_token": refresh, "grant_type": "refresh_token",
        ]), previous: previous)
    }

    public func revoke(_ tokens: GoogleOAuthTokens) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["token": tokens.refreshToken ?? tokens.accessToken])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw GoogleOAuthError.serviceUnavailable }
    }

    private func perform(_ request: URLRequest, previous: GoogleOAuthTokens?) async throws -> GoogleOAuthTokens {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleOAuthError.serviceUnavailable }
        if http.statusCode == 400 || http.statusCode == 401 { throw GoogleOAuthError.authorizationExpired }
        guard http.statusCode == 200, data.count <= 65_536 else { throw GoogleOAuthError.serviceUnavailable }
        guard let token = try? JSONDecoder().decode(Response.self, from: data),
              !token.access_token.isEmpty, token.access_token.utf8.count <= 16_384,
              token.token_type.lowercased() == "bearer", token.expires_in > 0, token.expires_in <= 86_400
        else { throw GoogleOAuthError.invalidTokenResponse }
        return GoogleOAuthTokens(accessToken: token.access_token, refreshToken: token.refresh_token ?? previous?.refreshToken,
                                 expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in)),
                                 scopes: token.scope.map { Set($0.split(separator: " ").map(String.init)) } ?? previous?.scopes ?? [])
    }

    static func request(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(fields)
        return request
    }
    private static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted(by: { $0.key < $1.key }).map { key, value in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
    }
}
