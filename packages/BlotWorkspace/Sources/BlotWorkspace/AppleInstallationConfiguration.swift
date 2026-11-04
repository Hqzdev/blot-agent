import Foundation

/// Build-managed credentials have a separate namespace from user connections and device identity.
public struct AppleInstallationConfiguration: Codable, Sendable {
    public struct GigaChat: Codable, Sendable {
        public let authorizationKey: String
        public let model: String
        public let apiURL: URL
        public let oauthURL: URL
        public let scope: String
        public let outputTokens: Int
        public let contextTokens: Int
        public let runTokenBudget: Int
        enum CodingKeys: String, CodingKey {
            case authorizationKey = "AuthorizationKey", model = "Model", apiURL = "APIURL", oauthURL = "OAuthURL"
            case scope = "Scope", outputTokens = "OutputTokens", contextTokens = "ContextTokens", runTokenBudget = "RunTokenBudget"
        }
    }
    public let profile: String
    public let revision: String
    public let authURL: URL?
    public let accountServiceURL: URL?
    public let gigaChat: GigaChat
    public let googleClientIDs: [String: String]
    public let providerCA: Data?
    enum CodingKeys: String, CodingKey {
        case authURL = "AuthURL"
        case profile = "Profile", revision = "Revision", accountServiceURL = "AccountServiceURL", gigaChat = "GigaChat"
        case googleClientIDs = "GoogleClientIDs", providerCA = "ProviderCA"
    }
    public static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "AppleInstallation", withExtension: "plist") else { throw ChatModelError.invalidConfiguration }
        return try decode(Data(contentsOf: url))
    }
    public static func decode(_ data: Data) throws -> Self {
        guard var object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ChatModelError.invalidConfiguration
        }
        if let ca = object["ProviderCA"] as? Data { object["ProviderCA"] = ca.base64EncodedString() }
        let value = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
        guard ["personal-dev", "public-beta"].contains(value.profile), value.gigaChat.outputTokens > 0,
              value.gigaChat.contextTokens > 0, value.gigaChat.runTokenBudget > 0 else { throw ChatModelError.invalidConfiguration }
        #if !DEBUG
        guard value.profile == "public-beta" else { throw ChatModelError.invalidConfiguration }
        #endif
        if let origin = value.accountServiceURL { _ = try WorkspaceCloudHTTP(origin: origin, allowLoopbackHTTP: true) }
        if value.profile == "public-beta" {
            guard value.gigaChat.authorizationKey.isEmpty, value.accountServiceURL?.scheme == "https",
                  value.authURL?.scheme == "https" else { throw ChatModelError.invalidConfiguration }
            for endpoint in [value.gigaChat.apiURL, value.gigaChat.oauthURL] {
                guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
                      endpoint.query == nil, endpoint.fragment == nil else { throw ChatModelError.invalidConfiguration }
            }
        } else {
            try ModelHTTP.validate(endpoint: value.gigaChat.apiURL, model: value.gigaChat.model, secret: value.gigaChat.authorizationKey)
            _ = try GigaChatTokenProvider(endpoint: value.gigaChat.oauthURL, authorizationKey: value.gigaChat.authorizationKey, scope: value.gigaChat.scope)
        }
        return value
    }
    public func install(credentials: any WorkspaceCredentialStore) async throws {
        // Replace only this managed item. No enumeration, deletion or migration of user OAuth tokens.
        try await credentials.write(PropertyListEncoder().encode(self), name: "apple-installation")
    }
    public func makeModel() throws -> GigaChatModel {
        guard !gigaChat.authorizationKey.isEmpty else { throw ChatModelError.invalidConfiguration }
        let hosts = Set([gigaChat.apiURL.host!, gigaChat.oauthURL.host!])
        let session = try ProviderTrustSession.make(certificatePEM: providerCA, hosts: hosts)
        let tokens = try GigaChatTokenProvider(endpoint: gigaChat.oauthURL, authorizationKey: gigaChat.authorizationKey,
            scope: gigaChat.scope, session: session)
        var endpoint = gigaChat.apiURL
        if !endpoint.path.hasSuffix("/chat/completions") { endpoint.appendPathComponent("chat/completions") }
        return try GigaChatModel(endpoint: endpoint, model: gigaChat.model, tokens: tokens, session: session)
    }
}
