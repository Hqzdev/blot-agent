import Foundation

/// One token refresh at a time. A failed completion is never silently regenerated.
public actor GigaChatTokenProvider {
    private struct Token: Decodable { let access_token: String; let expires_at: Int64 }
    private let endpoint: URL
    private let authorizationKey: String
    private let scope: String
    private let session: URLSession
    private var token: Token?
    private var refresh: Task<Token, Error>?
    public init(endpoint: URL, authorizationKey: String, scope: String = "GIGACHAT_API_PERS", session: URLSession? = nil) throws {
        try ModelHTTP.validate(endpoint: endpoint, model: scope, secret: authorizationKey)
        guard ["GIGACHAT_API_PERS", "GIGACHAT_API_B2B", "GIGACHAT_API_CORP"].contains(scope),
              Data(base64Encoded: authorizationKey) != nil else { throw ChatModelError.invalidConfiguration }
        self.endpoint = endpoint; self.authorizationKey = authorizationKey; self.scope = scope; self.session = session ?? ModelHTTP.makeSession()
    }
    public func accessToken() async throws -> String {
        if let token, Double(token.expires_at) / 1000 - Date().timeIntervalSince1970 > 60 { return token.access_token }
        let worker: Task<Token, Error>
        if let refresh { worker = refresh }
        else {
            let endpoint = endpoint, key = authorizationKey, scope = scope, session = session
            worker = Task {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"; request.timeoutInterval = 30
                request.setValue("Basic " + key, forHTTPHeaderField: "Authorization")
                request.setValue(UUID().uuidString, forHTTPHeaderField: "RqUID")
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(("scope=" + scope).utf8)
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw ChatModelError.invalidStream }
                guard (200..<300).contains(response.statusCode) else { throw ChatModelError.http(response.statusCode) }
                guard data.count <= 65536 else { throw ChatModelError.invalidStream }
                let result = try JSONDecoder().decode(Token.self, from: data)
                guard !result.access_token.isEmpty, !result.access_token.contains(where: { $0.isNewline }),
                      Double(result.expires_at) / 1000 > Date().timeIntervalSince1970 else { throw ChatModelError.invalidStream }
                return result
            }
            refresh = worker
        }
        do {
            let value = try await worker.value
            token = value; refresh = nil
            try Task.checkCancellation()
            return value.access_token
        } catch { refresh = nil; throw error }
    }
    public func invalidate() { token = nil }
}

public struct GigaChatModel: ChatModel {
    private let endpoint: URL
    private let model: String
    private let tokens: GigaChatTokenProvider
    private let session: URLSession
    public init(endpoint: URL, model: String, tokens: GigaChatTokenProvider, session: URLSession? = nil) throws {
        try ModelHTTP.validate(endpoint: endpoint, model: model, secret: "token-provider")
        self.endpoint = endpoint; self.model = model; self.tokens = tokens; self.session = session ?? ModelHTTP.makeSession()
    }
    public func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        ModelHTTP.stream(session: session, dialect: .gigaChat, onUnauthorized: { await tokens.invalidate() }) {
            try await ModelHTTP.request(endpoint: endpoint, token: tokens.accessToken(),
                body: ModelRequestEncoder.gigaChat(request, model: model))
        }
    }
}
