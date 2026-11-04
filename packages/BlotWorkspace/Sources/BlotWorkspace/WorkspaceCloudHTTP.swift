import Foundation

public enum WorkspaceCloudError: Error, Equatable, Sendable {
    case invalidConfiguration, invalidResponse, authenticationRequired
    case rejected(status: Int, code: String)
}

private final class CloudRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// All URLs are constructed below one configured origin; authenticated requests never follow redirects.
public actor WorkspaceCloudHTTP {
    private let origin: URL
    private let session: URLSession

    public init(origin: URL, allowLoopbackHTTP: Bool = false) throws {
        guard origin.host != nil, origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/",
              origin.scheme == "https" || (allowLoopbackHTTP && origin.scheme == "http" && origin.host == "127.0.0.1")
        else { throw WorkspaceCloudError.invalidConfiguration }
        self.origin = origin
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration, delegate: CloudRedirectPolicy(), delegateQueue: nil)
    }

    public func request<Response: Decodable & Sendable>(_ type: Response.Type, method: String, path: [String],
        query: [String: String] = [:], body: Data? = nil, accessToken: String? = nil) async throws -> Response {
        let data = try await perform(method: method, path: path, query: query, body: body, accessToken: accessToken)
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw WorkspaceCloudError.invalidResponse }
    }

    public func empty(method: String, path: [String], body: Data? = nil, accessToken: String? = nil) async throws {
        _ = try await perform(method: method, path: path, query: [:], body: body, accessToken: accessToken)
    }

    private func perform(method: String, path: [String], query: [String: String], body: Data?, accessToken: String?) async throws -> Data {
        guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }),
              ["GET", "POST", "PUT", "DELETE"].contains(method), (body?.count ?? 0) <= 1_048_576,
              accessToken.map({ !$0.isEmpty && !$0.contains(where: { $0.isNewline }) }) ?? true else { throw WorkspaceCloudError.invalidConfiguration }
        var url = origin
        for segment in path { url.appendPathComponent(segment) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.sorted(by: { $0.key < $1.key }).map { .init(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let accessToken { request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw WorkspaceCloudError.invalidResponse }
        var data = Data()
        // A batch of 50 maximum-size changes is bounded to 40 MiB after base64 encoding.
        for try await byte in bytes {
            guard data.count < 40 * 1024 * 1024 else { throw WorkspaceCloudError.invalidResponse }
            data.append(byte)
        }
        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let code: String }
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.code ?? "http_error"
            if code == "replay_unavailable" { throw WorkspaceSyncError.replayUnavailable }
            throw WorkspaceCloudError.rejected(status: http.statusCode, code: code)
        }
        return data
    }
}

public protocol WorkspaceCloudAuthorization: Sendable {
    func accessToken() async throws -> String
}

public struct WorkspaceCloudSyncTransport: WorkspaceSyncTransport {
    private let http: WorkspaceCloudHTTP
    private let authorization: any WorkspaceCloudAuthorization
    public init(http: WorkspaceCloudHTTP, authorization: any WorkspaceCloudAuthorization) {
        self.http = http; self.authorization = authorization
    }
    public func hasAccepted(changeID: UUID) async throws -> Bool {
        struct Receipt: Decodable, Sendable { let accepted: Bool }
        return try await http.request(Receipt.self, method: "GET", path: ["v1", "relay", "changes", changeID.uuidString, "receipt"], accessToken: authorization.accessToken()).accepted
    }
    public func upload(_ packet: WorkspaceEncryptedPacket) async throws -> UUID {
        struct Receipt: Decodable, Sendable { let changeID: UUID }
        return try await http.request(Receipt.self, method: "POST", path: ["v1", "relay", "changes"],
            body: JSONEncoder().encode(packet), accessToken: authorization.accessToken()).changeID
    }
    public func pull(after cursor: Int64, limit: Int) async throws -> WorkspaceRelayBatch {
        try await http.request(WorkspaceRelayBatch.self, method: "GET", path: ["v1", "relay", "changes"],
            query: ["after": String(cursor), "limit": String(limit)], accessToken: authorization.accessToken())
    }
    public func acknowledge(upTo cursor: Int64) async throws {
        struct Ack: Encodable { let cursor: Int64 }
        try await http.empty(method: "POST", path: ["v1", "relay", "ack"], body: JSONEncoder().encode(Ack(cursor: cursor)), accessToken: authorization.accessToken())
    }
}
