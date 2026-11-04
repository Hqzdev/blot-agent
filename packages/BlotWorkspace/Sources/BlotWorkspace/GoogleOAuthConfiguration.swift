import Foundation

public enum GoogleOAuthError: Error, Equatable, Sendable {
    case notConfigured, invalidConfiguration, invalidScopes, invalidCallback, accessDenied
    case invalidTokenResponse, authorizationExpired, serviceUnavailable
}

public struct GoogleOAuthConfiguration: Equatable, Sendable {
    public enum Platform: String, Sendable { case iOS, macOS }
    public let clientID: String
    public let redirectURI: URL

    public init(clientID: String, redirectURI: URL) throws {
        guard clientID.range(of: #"^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil,
              redirectURI.absoluteString == clientID.split(separator: ".").reversed().joined(separator: ".") + ":/oauthredirect"
        else { throw GoogleOAuthError.invalidConfiguration }
        self.clientID = clientID
        self.redirectURI = redirectURI
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
        return try Self(clientID: clientID, redirectURI: uri)
    }
}

public enum GoogleAccess: String, CaseIterable, Sendable {
    case gmailRead, gmailDrafts, gmailSend, calendarList, calendarRead, calendarWrite, calendarFreeBusy

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
        }
        return base + suffix
    }
}
