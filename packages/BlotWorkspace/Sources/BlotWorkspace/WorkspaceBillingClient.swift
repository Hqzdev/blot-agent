import CryptoKit
import Foundation

public struct WorkspaceBillingOverview: Decodable, Sendable {
    public struct Payment: Decodable, Sendable, Identifiable {
        public let paymentId: UUID; public let plan: String; public let amountMinor: Int; public let currency: String; public let status: String; public let test: Bool; public let createdAt: String
        public var id: UUID { paymentId }
    }
    public struct Usage: Decodable, Sendable {
        public struct Window: Decodable, Sendable {
            public let hours: Int
            public let percent: Int
            public let resetsAt: String?
        }
        public let plan: String
        public let test: Bool
        public let enforced: Bool
        public let windows: [Window]
    }
    public let usage: Usage?
    public let plan: String
    public let payments: [Payment]
    public var hasSubscription: Bool {
        (usage?.plan ?? plan) != "free"
    }
}
public actor WorkspaceBillingClient {
    private let authorization: any WorkspaceCloudAuthorization
    private let session: URLSession
    private let credentials: any WorkspaceCredentialStore
    public init(authorization: any WorkspaceCloudAuthorization, credentials: any WorkspaceCredentialStore) {
        self.credentials = credentials
        self.authorization = authorization
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: BillingNoRedirects(), delegateQueue: nil)
    }
    public func overview(includePayments: Bool = true) async throws -> WorkspaceBillingOverview {
        let data = try await request(includePayments ? "overview" : "overview?view=subscription", method: "GET")
        let result = try JSONDecoder().decode(WorkspaceBillingOverview.self, from: data)
        guard ["free", "premium", "super", "ultra", "team"].contains(result.plan), result.payments.count <= 100 else { throw WorkspaceCloudError.invalidResponse }
        return result
    }
    public func cancel() async throws { _ = try await request("subscription", method: "DELETE") }
    #if os(macOS)
    private static let platform = "macos"
    #else
    private static let platform = "ios"
    #endif
    public static var callbackScheme: String { "blot-agent-" + platform }

    public func startCheckout(cardID: UUID? = nil) async throws -> URL {
        let verifier = SymmetricKey(size: .bits256).withUnsafeBytes { Self.base64URL(Data($0)) }
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var fields = ["action": "start", "challenge": challenge, "platform": Self.platform]
        #if DEBUG
        if let invite = try await credentials.read("billing-pilot-invitation") {
            fields["invitation"] = String(decoding: invite, as: UTF8.self)
        }
        #endif
        let data = try await request("return", method: "POST", fields: fields)
        struct Attempt: Decodable { let id: UUID }
        let id = try JSONDecoder().decode(Attempt.self, from: data).id
        try await credentials.write(Data(verifier.utf8), name: "billing-return-" + id.uuidString)
        var url = URLComponents(string: "https://blot-agent.vercel.app/app/pricing")!
        var items = [URLQueryItem(name: "attemptId", value: id.uuidString)]
        if let cardID { items.append(URLQueryItem(name: "cardId", value: cardID.uuidString)) }
        url.queryItems = items
        return url.url!
    }
    public func redeem(_ url: URL) async throws -> UUID? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard url.scheme == Self.callbackScheme, url.host == "billing", url.path == "/return",
              let id = UUID(uuidString: items.first(where: { $0.name == "id" })?.value ?? ""),
              let code = items.first(where: { $0.name == "code" })?.value, code.utf8.count == 43,
              let data = try await credentials.read("billing-return-" + id.uuidString),
              let verifier = String(data: data, encoding: .utf8) else { throw WorkspaceCloudError.invalidResponse }
        struct Result: Decodable { let cardID: UUID? }
        let result = try await request("return", method: "POST", fields: ["action": "redeem", "id": id.uuidString, "code": code, "verifier": verifier])
        try await credentials.remove("billing-return-" + id.uuidString)
        return try JSONDecoder().decode(Result.self, from: result).cardID
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private func request(_ endpoint: String, method: String, fields: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://blot-agent.vercel.app/app/api/billing/" + endpoint)!)
        request.httpMethod = method
        if let fields {
            request.httpBody = try JSONEncoder().encode(fields)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer " + (try await authorization.accessToken()), forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw WorkspaceCloudError.invalidResponse }
        var data = Data(); for try await byte in bytes { guard data.count < 128_000 else { throw WorkspaceCloudError.invalidResponse }; data.append(byte) }
        return data
    }
}
private final class BillingNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
