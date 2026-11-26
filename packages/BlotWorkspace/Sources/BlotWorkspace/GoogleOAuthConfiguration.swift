import Foundation

public enum GoogleOAuthError: Error, Equatable, Sendable {
    case notConfigured, invalidConfiguration, invalidScopes, invalidCallback, accessDenied
    case invalidTokenResponse, authorizationExpired, serviceUnavailable, clientSecretRequired, apiNotEnabled
}

public struct GoogleOAuthConfiguration: Equatable, Sendable {
    public enum Platform: String, Sendable { case iOS, macOS }
    public let clientID: String
    public let redirectURI: URL
    let clientSecret: String?
    public var usesLoopback: Bool { redirectURI.scheme == "http" }

    public init(clientID: String, redirectURI: URL, clientSecret: String? = nil) throws {
        let loopback = redirectURI.scheme == "http" && redirectURI.host == "127.0.0.1" && redirectURI.path == "/oauthredirect"
            && redirectURI.user == nil && redirectURI.password == nil && redirectURI.query == nil && redirectURI.fragment == nil
            && (redirectURI.port.map { (1...65535).contains($0) } ?? true)
        guard clientID.range(of: #"^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil,
              loopback || redirectURI.absoluteString == clientID.split(separator: ".").reversed().joined(separator: ".") + ":/oauthredirect",
              clientSecret.map({ !$0.isEmpty && $0.utf8.count <= 4096 && !$0.contains(where: { $0.isNewline || $0 == "\0" }) }) ?? true
        else { throw GoogleOAuthError.invalidConfiguration }
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.clientSecret = clientSecret
    }

    public func loopback(port: UInt16) throws -> Self {
        guard usesLoopback, port > 0, let uri = URL(string: "http://127.0.0.1:\(port)/oauthredirect") else { throw GoogleOAuthError.invalidConfiguration }
        return try .init(clientID: clientID, redirectURI: uri, clientSecret: clientSecret)
    }

    public static func load(plist: Data, platform: Platform, bundleID: String) throws -> Self {
        guard let root = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else {
            throw GoogleOAuthError.invalidConfiguration
        }
        guard root["Enabled"] as? Bool == true else { throw GoogleOAuthError.notConfigured }
        guard let clients = root["Clients"] as? [String: [String: String]],
              let client = clients[platform.rawValue], client["BundleID"] == bundleID,
              let clientID = client["ClientID"], let rawURI = client["RedirectURI"], let uri = URL(string: rawURI)
        else { throw GoogleOAuthError.invalidConfiguration }
        let configuration = try Self(clientID: clientID, redirectURI: uri, clientSecret: client["ClientSecret"])
        if platform == .macOS {
            guard configuration.usesLoopback else { throw GoogleOAuthError.invalidConfiguration }
            guard configuration.clientSecret != nil else { throw GoogleOAuthError.clientSecretRequired }
        } else if configuration.usesLoopback { throw GoogleOAuthError.invalidConfiguration }
        return configuration
    }
}

public enum GoogleAccess: String, CaseIterable, Sendable {
    case gmailRead, gmailDrafts, gmailSend, calendarList, calendarRead, calendarWrite, calendarFreeBusy, driveRead, driveFile

    public var scope: String {
        let base = "https://www.googleapis.com/auth/"
        let suffix = switch self {
        case .gmailRead: "gmail.readonly"
        case .gmailDrafts: "gmail.compose"
        case .gmailSend: "gmail.send"
        case .calendarList: "calendar.calendarlist.readonly"
        case .calendarRead: "calendar.events.readonly"
        case .calendarWrite: "calendar.events"
        case .calendarFreeBusy: "calendar.freebusy"
        case .driveRead: "drive.readonly"
        case .driveFile: "drive.file"
        }
        return base + suffix
    }
}
