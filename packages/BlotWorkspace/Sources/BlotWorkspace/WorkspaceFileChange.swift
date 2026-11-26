import CryptoKit
import Foundation

/// Durable evidence for one successful local write; an undo remains a checked new write.
public struct WorkspaceFileChange: Codable, Sendable, Identifiable {
    public let id: UUID
    public let actionID: UUID
    public let sourceID: UUID
    public let agentID: UUID
    public let callID: String
    public let path: String
    public let directoryID: String
    public let before: String?
    public let after: String
    public let expectedHash: String
    public let resultHash: String
    public var created: Bool { expectedHash == "missing" }
    public var canUndo: Bool { !created && before != nil }
    public var difference: WorkspaceTextDifference { .init(before: before ?? "", after: after) }
    public static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    public static func artifactName(_ id: UUID) -> String { "blot-change-" + id.uuidString + ".json" }
    public static func isInternalArtifact(name: String) -> Bool {
        name.range(of: #"^blot-change-[A-Fa-f0-9-]{36}\.json$"#, options: .regularExpression) != nil
    }
}

public struct WorkspaceTextDifference: Sendable {
    public let added: Int
    public let removed: Int
    public init(before: String, after: String) {
        func lines(_ text: String) -> [String] {
            guard !text.isEmpty else { return [] }
            var lines = text.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }; return lines
        }
        let old = lines(before), new = lines(after)
        if max(old.count, new.count) <= 2000 {
            let changes = new.difference(from: old)
            added = changes.insertions.count; removed = changes.removals.count
        } else {
            let prefix = zip(old, new).prefix { $0 == $1 }.count
            let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed()).prefix { $0 == $1 }.count
            added = new.count - prefix - suffix; removed = old.count - prefix - suffix
        }
    }
}
