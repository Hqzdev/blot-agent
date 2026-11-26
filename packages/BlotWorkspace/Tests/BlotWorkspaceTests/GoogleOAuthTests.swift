import CryptoKit
import Foundation
import Testing
@testable import BlotWorkspace

struct GoogleOAuthTests {
    @Test func desktopCallbackIsBoundToEphemeralLoopbackAndSecretStaysOutOfBrowser() throws {
        let config = try GoogleOAuthConfiguration(clientID: "123456-test.apps.googleusercontent.com",
            redirectURI: URL(string: "http://127.0.0.1/oauthredirect")!, clientSecret: "desktop-test+secret&value")
        #expect(throws: GoogleOAuthError.invalidConfiguration) { try GoogleOAuthAuthorization(configuration: config, access: [.driveFile]) }
        let bound = try config.loopback(port: 49152)
        let auth = try GoogleOAuthAuthorization(configuration: bound, access: [.driveFile])
        let query = URLComponents(url: auth.url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(!auth.url.absoluteString.contains("desktop-test"))
        #expect(!query.contains { $0.name == "client_secret" || $0.name == "code_verifier" })
        let state = query.first { $0.name == "state" }!.value!
        let callback = URL(string: bound.redirectURI.absoluteString + "?state=\(state)&code=test")!
        let request = try auth.tokenRequest(callback: callback)
        let fields = URLComponents(string: "https://test/?" + String(decoding: request.httpBody!, as: UTF8.self))!.queryItems!
        #expect(fields.first { $0.name == "client_secret" }?.value == "desktop-test+secret&value")
        #expect(fields.first { $0.name == "redirect_uri" }?.value == bound.redirectURI.absoluteString)
        for invalid in ["http://127.0.0.1:49153/oauthredirect", "http://localhost:49152/oauthredirect", "http://127.0.0.2:49152/oauthredirect"] {
            #expect(throws: GoogleOAuthError.invalidCallback) { try auth.tokenRequest(callback: URL(string: invalid + "?state=\(state)&code=test")!) }
        }
        #expect(throws: GoogleOAuthError.invalidConfiguration) {
            try GoogleOAuthConfiguration(clientID: config.clientID, redirectURI: URL(string: "http://0.0.0.0:49152/oauthredirect")!, clientSecret: "test")
        }
    }

    @Test func macBuildRequiresItsOwnDesktopCredentialAndIOSRejectsLoopback() throws {
        let client: [String: String] = ["ClientID": "123456-test.apps.googleusercontent.com", "BundleID": "yaroslavstrelkov.blot-agent", "RedirectURI": "http://127.0.0.1/oauthredirect"]
        func plist(_ client: [String: String], platform: String) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["Enabled": true, "Clients": [platform: client]], format: .xml, options: 0)
        }
        #expect(throws: GoogleOAuthError.clientSecretRequired) {
            try GoogleOAuthConfiguration.load(plist: plist(client, platform: "macOS"), platform: .macOS, bundleID: "yaroslavstrelkov.blot-agent")
        }
        let configured = client.merging(["ClientSecret": "test-native-secret"]) { $1 }
        #expect(try GoogleOAuthConfiguration.load(plist: plist(configured, platform: "macOS"), platform: .macOS, bundleID: "yaroslavstrelkov.blot-agent").usesLoopback)
        #expect(throws: GoogleOAuthError.invalidConfiguration) {
            try GoogleOAuthConfiguration.load(plist: plist(configured, platform: "iOS"), platform: .iOS, bundleID: "yaroslavstrelkov.blot-agent")
        }
    }
    @Test func pkceBindsCallbackAndDoesNotSendVerifierToBrowser() throws {
        let config = try GoogleOAuthConfiguration(clientID: "123456-test.apps.googleusercontent.com",
            redirectURI: URL(string: "com.googleusercontent.apps.123456-test:/oauthredirect")!)
        let first = try GoogleOAuthAuthorization(configuration: config, access: [.gmailRead])
        let second = try GoogleOAuthAuthorization(configuration: config, access: [.gmailRead])
        let query = URLComponents(url: first.url, resolvingAgainstBaseURL: false)!.queryItems!
        let state = query.first(where: { $0.name == "state" })!.value!
        #expect(!query.contains(where: { $0.name == "code_verifier" || $0.name == "client_secret" }))
        let callback = URL(string: config.redirectURI.absoluteString + "?state=\(state)&code=test%2Bcode")!
        let request = try first.tokenRequest(callback: callback)
        #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        let fields = URLComponents(string: "https://local.test/?" + body)!.queryItems!
        let verifier = fields.first(where: { $0.name == "code_verifier" })!.value!
        let digest = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        #expect(query.first(where: { $0.name == "code_challenge" })?.value == digest)
        #expect(fields.first(where: { $0.name == "code" })?.value == "test+code")
        #expect(throws: GoogleOAuthError.invalidCallback) { try second.tokenRequest(callback: callback) }
        #expect(throws: GoogleOAuthError.invalidCallback) {
            try first.tokenRequest(callback: URL(string: config.redirectURI.absoluteString + "?state=\(state)&state=\(state)&code=x")!)
        }
        #expect(throws: GoogleOAuthError.invalidCallback) {
            try first.tokenRequest(callback: URL(string: "com.googleusercontent.apps.123456-test:/wrong?state=\(state)&code=x")!)
        }
    }

    @Test func configurationRequiresEnabledMatchingNativeClient() throws {
        let disabled = try PropertyListSerialization.data(fromPropertyList: ["Enabled": false, "Clients": [:]] as [String: Any], format: .xml, options: 0)
        #expect(throws: GoogleOAuthError.notConfigured) {
            try GoogleOAuthConfiguration.load(plist: disabled, platform: .iOS, bundleID: "yaroslavstrelkov.blot-agent.ios")
        }
        let enabled = try PropertyListSerialization.data(fromPropertyList: ["Enabled": true, "Clients": ["iOS": [
            "ClientID": "123456-test.apps.googleusercontent.com", "BundleID": "yaroslavstrelkov.blot-agent.ios",
            "RedirectURI": "com.googleusercontent.apps.123456-test:/oauthredirect"]]] as [String: Any], format: .xml, options: 0)
        #expect(throws: GoogleOAuthError.invalidConfiguration) {
            try GoogleOAuthConfiguration.load(plist: enabled, platform: .macOS, bundleID: "yaroslavstrelkov.blot-agent")
        }
        let config = try GoogleOAuthConfiguration.load(plist: enabled, platform: .iOS, bundleID: "yaroslavstrelkov.blot-agent.ios")
        #expect(config.clientID == "123456-test.apps.googleusercontent.com")
        #expect(throws: GoogleOAuthError.invalidScopes) { try GoogleOAuthAuthorization(configuration: config, access: []) }
    }
}
