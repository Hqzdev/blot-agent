import Foundation

/// Build-managed credentials have a separate namespace from user connections and device identity.
public struct AppleInstallationConfiguration: Codable, Sendable {
    public struct GigaChat: Codable, Sendable {
        public let authorizationKey: String?
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
        guard value.gigaChat.outputTokens > 0,
              value.gigaChat.contextTokens > 0, value.gigaChat.runTokenBudget > 0 else { throw ChatModelError.invalidConfiguration }
        if value.profile == "public-beta" {
            guard value.gigaChat.authorizationKey == nil, value.authURL?.scheme == "https",
                  let origin = value.accountServiceURL, origin.scheme == "https" else { throw ChatModelError.invalidConfiguration }
            _ = try WorkspaceCloudHTTP(origin: origin, allowLoopbackHTTP: false)
            return value
        }
        #if DEBUG
        guard value.profile == "personal-dev" else { throw ChatModelError.invalidConfiguration }
        if let origin = value.accountServiceURL { _ = try WorkspaceCloudHTTP(origin: origin, allowLoopbackHTTP: true) }
        if let key = value.gigaChat.authorizationKey {
            try ModelHTTP.validate(endpoint: value.gigaChat.apiURL, model: value.gigaChat.model, secret: key)
            _ = try GigaChatTokenProvider(endpoint: value.gigaChat.oauthURL, authorizationKey: key, scope: value.gigaChat.scope)
        }
        return value
        #else
        throw ChatModelError.invalidConfiguration
        #endif
    }
    public func install(credentials: any WorkspaceCredentialStore) async throws {
        // Replace only this managed item. No enumeration, deletion or migration of user OAuth tokens.
        try await credentials.write(PropertyListEncoder().encode(self), name: "apple-installation")
    }
    public func makeModel() throws -> GigaChatModel {
        guard let key = gigaChat.authorizationKey else { throw ChatModelError.invalidConfiguration }
        let hosts = Set([gigaChat.apiURL.host!, gigaChat.oauthURL.host!])
        let session = try ProviderTrustSession.make(certificatePEM: providerCA, hosts: hosts)
        let tokens = try GigaChatTokenProvider(endpoint: gigaChat.oauthURL, authorizationKey: key,
            scope: gigaChat.scope, session: session)
        var endpoint = gigaChat.apiURL
        if !endpoint.path.hasSuffix("/chat/completions") { endpoint.appendPathComponent("chat/completions") }
        return try GigaChatModel(endpoint: endpoint, model: gigaChat.model, tokens: tokens, session: session)
    }
}
