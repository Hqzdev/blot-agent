import Foundation

/// The private control envelope must never become a chat message, even on parse failure.
public struct WorkspaceGroupConclusion: Decodable, Sendable {
    public let summary: String
    public let completed: Bool
    public enum Failure: Error { case invalidFormat }

    public static func decode(_ text: String) throws -> Self {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first <= last,
              var value = try? JSONDecoder().decode(Self.self, from: Data(text[first...last].utf8)) else { throw Failure.invalidFormat }
        for _ in 0..<3 {
            let summary = value.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { throw Failure.invalidFormat }
            // Some providers wrap the private envelope again inside its summary.
            if let nested = try? JSONDecoder().decode(Self.self, from: Data(summary.utf8)) {
                value = Self(summary: nested.summary, completed: value.completed && nested.completed)
            } else {
                guard summary.range(of: #""(?:summary|completed)"\s*:"#, options: .regularExpression) == nil else { throw Failure.invalidFormat }
                return Self(summary: summary, completed: value.completed)
            }
        }
        throw Failure.invalidFormat
    }
}
