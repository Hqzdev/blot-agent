import CryptoKit
import Foundation
import Testing
@testable import BlotWorkspace

struct GoogleOAuthTests {
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
