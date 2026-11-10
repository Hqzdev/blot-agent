import Foundation

public struct WidgetSnapshotStore: Sendable {
    public static let groupIdentifier = "group.yaroslavstrelkov.blot-agent.ios"
    private let directory: URL?
    public enum Failure: Error { case unavailableContainer, unsupportedVersion }

    public init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)) {
        self.directory = directory
    }

    public func read() throws -> WidgetSnapshot? {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let result = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: url))
        guard result.version == 1 else { throw Failure.unsupportedVersion }
        return result
    }

    @discardableResult public func write(_ snapshot: WidgetSnapshot) throws -> Bool {
        let url = try fileURL()
        if let previous = try? read() {
            var comparable = snapshot
            comparable.updatedAt = previous.updatedAt
            if comparable == previous, snapshot.updatedAt.timeIntervalSince(previous.updatedAt) < 60 { return false }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        return true
    }

    private func fileURL() throws -> URL {
        guard let directory else { throw Failure.unavailableContainer }
        return directory.appendingPathComponent("WidgetSnapshot.json")
    }
}
