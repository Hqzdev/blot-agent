import Foundation

/// Explicit read/discovery constraints on the current user turn narrow persistent grants.
public struct WorkspaceToolRestrictions: Sendable {
    private let discoveryOnly: Bool
    private let readOnly: Bool
    private let noSending: Bool
    public var onlyResourceDiscovery: Bool { discoveryOnly }
    public init(userRequest: String) {
        let text = userRequest.lowercased()
        func matches(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        discoveryOnly = matches(#"только\s+(обнаружени\p{L}*\s+ресурс|(?:реальные\s+)?списк\p{L}*\s+ресурс)|only\s+(?:resource\s+discovery|discover\s+resources|list\s+resources)"#)
        readOnly = discoveryOnly || matches(#"только\s+чтени|read[ -]only|no\s+changes|ничего\s+не\s+(?:созда|меня|изменя)|не\s+(?:создавай\p{L}*|создавать|изменяй\p{L}*|изменять)"#)
        noSending = matches(#"не\s+отправ\p{L}*|do\s+not\s+send|don.t\s+send"#)
    }
    public func allows(operation: String) -> Bool {
        if discoveryOnly { return operation == "resources" }
        if readOnly { return ["resources", "list", "read", "search"].contains(operation) }
        return !(noSending && operation == "send")
    }
}
