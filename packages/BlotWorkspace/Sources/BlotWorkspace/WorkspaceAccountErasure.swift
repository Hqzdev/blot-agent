import Foundation

/// A durable local cleanup intent, written only after cloud deletion succeeds.
public struct WorkspaceAccountErasure: Sendable {
    private struct Intent: Codable { let ownerID: UUID; let workspaceIDs: [UUID]; let deviceID: UUID }
    private let root: URL
    private let credentials: any WorkspaceCredentialStore
    public init(root: URL, credentials: any WorkspaceCredentialStore) { self.root = root; self.credentials = credentials }
    private var marker: URL { root.appendingPathComponent("pending-account-deletion.json") }
    public func mark(_ identity: WorkspaceIdentity) throws {
        let folder = try accountFolder(identity.ownerID)
        let old = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let ids = Set(old.compactMap { UUID(uuidString: $0.lastPathComponent) }).union([identity.workspaceID])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try WorkspaceCoding.encode(Intent(ownerID: identity.ownerID, workspaceIDs: ids.sorted { $0.uuidString < $1.uuidString }, deviceID: identity.deviceID)).write(to: marker, options: .atomic)
    }
    public func resume(removeAdditionalCredentials: @Sendable (UUID) async throws -> Void = { _ in }) async throws {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: marker.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) < 32_768 else { throw WorkspaceStorageError.invalidRecord }
        let intent = try WorkspaceCoding.decode(Intent.self, from: Data(contentsOf: marker))
        guard !intent.workspaceIDs.isEmpty, intent.workspaceIDs.count <= 100 else { throw WorkspaceStorageError.invalidRecord }
        let folder = try accountFolder(intent.ownerID)
        var locks: [WorkspaceProcessLock] = []
        for id in intent.workspaceIDs {
            let directory = folder.appendingPathComponent(id.uuidString)
            guard directory.resolvingSymlinksInPath().path.hasPrefix(folder.path + "/") else { throw WorkspaceFileError.unsafePath }
            if FileManager.default.fileExists(atPath: directory.path) { locks.append(try WorkspaceProcessLock(directory: directory)) }
        }
        defer { _ = locks }
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        var prefixes = ["profile:" + intent.ownerID.uuidString, "mcp:" + intent.ownerID.uuidString + ":", "native-projects:" + intent.ownerID.uuidString + ":", "browser:" + intent.ownerID.uuidString + ":", "session-directories:" + intent.ownerID.uuidString + ":"]
        for workspace in intent.workspaceIDs {
            prefixes += ["device-keys:", "device-authority:", "device-trust-v2:"].map { $0 + workspace.uuidString + ":" }
            for prefix in prefixes.suffix(3) { try await credentials.remove(prefix + intent.deviceID.uuidString) }
        }
        try await credentials.remove("profile:" + intent.ownerID.uuidString)
        if let pruning = credentials as? any WorkspaceCredentialPruning { try await pruning.removeNames(prefixes: prefixes) }
        if let data = try await credentials.read("account-session"), let tokens = try? WorkspaceCoding.decode(WorkspaceCloudTokens.self, from: data), tokens.ownerID == intent.ownerID {
            try await credentials.remove("account-session")
        }
        try await removeAdditionalCredentials(intent.ownerID)
        try FileManager.default.removeItem(at: marker)
    }
    private func accountFolder(_ owner: UUID) throws -> URL {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let folder = base.appendingPathComponent(owner.uuidString).resolvingSymlinksInPath()
        guard folder.path == base.appendingPathComponent(owner.uuidString).path else { throw WorkspaceFileError.unsafePath }
        return folder
    }
}
