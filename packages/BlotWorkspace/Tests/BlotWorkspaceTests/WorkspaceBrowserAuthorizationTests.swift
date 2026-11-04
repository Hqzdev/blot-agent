import CryptoKit
import Foundation
import Testing
@testable import BlotWorkspace

@Test func publicBetaAcceptsCredentialFreeConfigurationAndRejectsEmbeddedModelKeys() throws {
    var raw: [String: Any] = ["Profile": "public-beta", "Revision": "beta", "AuthURL": "https://example.com/login",
        "AccountServiceURL": "https://example.com", "GoogleClientIDs": [:], "GigaChat": [
            "AuthorizationKey": "", "Model": "GigaChat", "APIURL": "https://api.giga.chat/v1/",
            "OAuthURL": "https://ngw.devices.sberbank.ru:9443/api/v2/oauth", "Scope": "GIGACHAT_API_PERS",
            "OutputTokens": 64, "ContextTokens": 4096, "RunTokenBudget": 10000]]
    let configuration = try AppleInstallationConfiguration.decode(PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0))
    #expect(configuration.profile == "public-beta")
    #expect(throws: ChatModelError.invalidConfiguration) { _ = try configuration.makeModel() }
    var model = raw["GigaChat"] as! [String: Any]
    model["AuthorizationKey"] = Data("test:only".utf8).base64EncodedString()
    raw["GigaChat"] = model
    let data = try PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0)
    #expect(throws: ChatModelError.invalidConfiguration) { _ = try AppleInstallationConfiguration.decode(data) }
}

@Test func browserCallbackBindsStateClientAndPKCEWithoutCarryingSessionTokens() throws {
    let authorization = try WorkspaceBrowserAuthorization(loginURL: URL(string: "https://blot-agent.vercel.app/login")!, platform: "ios")
    let items = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems)
    let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    #expect(fields["client_id"] == "blot-ios")
    #expect(fields["code_challenge_method"] == "S256")
    let state = try #require(fields["state"])
    var callback = URLComponents(url: authorization.callbackURL, resolvingAgainstBaseURL: false)!
    callback.queryItems = [.init(name: "code", value: String(repeating: "c", count: 43)), .init(name: "state", value: state)]
    let exchange = try authorization.exchange(callback: callback.url!)
    let challenge = Data(SHA256.hash(data: Data(exchange.codeVerifier.utf8))).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    #expect(fields["code_challenge"] == challenge)
    #expect(exchange.redirectURI == "blot-agent-ios:/oauth/account")
    callback.queryItems?.append(.init(name: "state", value: state))
    #expect(throws: WorkspaceCloudError.authenticationRequired) { _ = try authorization.exchange(callback: callback.url!) }
    callback.queryItems?.removeLast()
    callback.queryItems?.append(.init(name: "access_token", value: "never-accept-tokens-in-url"))
    #expect(throws: WorkspaceCloudError.authenticationRequired) { _ = try authorization.exchange(callback: callback.url!) }
}

@Test func browserAttemptRejectsOtherPlatformCallbackAndInsecureLoginOrigin() throws {
    let authorization = try WorkspaceBrowserAuthorization(loginURL: URL(string: "https://example.com/login")!, platform: "macos")
    let state = URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
    let callback = URL(string: "blot-agent-ios:/oauth/account?state=" + state + "&code=" + String(repeating: "c", count: 43))!
    #expect(throws: WorkspaceCloudError.authenticationRequired) { _ = try authorization.exchange(callback: callback) }
    for url in ["http://example.com/login", "https://user:password@example.com/login", "https://example.com/login#fragment"] {
        #expect(throws: WorkspaceCloudError.invalidConfiguration) { _ = try WorkspaceBrowserAuthorization(loginURL: URL(string: url)!, platform: "ios") }
    }
}

@Test func installationPlistUsesStringURLsAndNeverRequiresSourceEnvironmentAtRuntime() throws {
    let raw: [String: Any] = ["Profile": "personal-dev", "Revision": "test", "AuthURL": "https://example.com/login",
        "AccountServiceURL": "https://example.com", "GoogleClientIDs": [:], "GigaChat": [
            "AuthorizationKey": Data("test:only".utf8).base64EncodedString(), "Model": "GigaChat", "APIURL": "https://api.giga.chat/v1/",
            "OAuthURL": "https://ngw.devices.sberbank.ru:9443/api/v2/oauth", "Scope": "GIGACHAT_API_PERS",
            "OutputTokens": 64, "ContextTokens": 4096, "RunTokenBudget": 10000]]
    let config = try AppleInstallationConfiguration.decode(PropertyListSerialization.data(fromPropertyList: raw, format: .xml, options: 0))
    #expect(config.authURL?.path == "/login")
    #expect(config.gigaChat.apiURL.host == "api.giga.chat")
    #expect(config.accountServiceURL?.host == "example.com")
}
