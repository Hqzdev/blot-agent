import CryptoKit
import Foundation
import OSLog

public struct WorkspaceCloudBackupManifest: Codable, Equatable, Sendable {
    public let snapshotID: UUID
    public let deviceID: UUID
    public let digest: String
    public let byteCount: Int
    public let chunkCount: Int
}

public protocol WorkspaceCloudBackupTransport: Sendable {
    func manifests() async throws -> [WorkspaceCloudBackupManifest]
    func begin(_ manifest: WorkspaceCloudBackupManifest) async throws
    func upload(snapshotID: UUID, part: Int, data: Data) async throws
    func commit(snapshotID: UUID) async throws
    func download(snapshotID: UUID, part: Int) async throws -> Data
}

public struct WorkspaceHTTPBackupTransport: WorkspaceCloudBackupTransport {
    private let http: WorkspaceCloudHTTP
    private let authorization: any WorkspaceCloudAuthorization
    public init(http: WorkspaceCloudHTTP, authorization: any WorkspaceCloudAuthorization) {
        self.http = http; self.authorization = authorization
    }
    public func manifests() async throws -> [WorkspaceCloudBackupManifest] {
        try await http.request([WorkspaceCloudBackupManifest].self, method: "GET", path: ["v1", "workspace", "backups"],
            accessToken: authorization.accessToken())
    }
    public func begin(_ manifest: WorkspaceCloudBackupManifest) async throws {
        try await http.empty(method: "POST", path: ["v1", "workspace", "backups"],
            body: JSONEncoder().encode(manifest), accessToken: authorization.accessToken())
    }
    public func upload(snapshotID: UUID, part: Int, data: Data) async throws {
        struct Part: Encodable { let data: Data }
        try await http.empty(method: "POST", path: path(snapshotID, part: part),
            body: JSONEncoder().encode(Part(data: data)), accessToken: authorization.accessToken())
    }
    public func commit(snapshotID: UUID) async throws {
        try await http.empty(method: "POST", path: ["v1", "workspace", "backups", snapshotID.uuidString, "commit"],
            accessToken: authorization.accessToken())
    }
    public func download(snapshotID: UUID, part: Int) async throws -> Data {
        struct Part: Decodable, Sendable { let data: Data }
        return try await http.request(Part.self, method: "GET", path: path(snapshotID, part: part),
            accessToken: authorization.accessToken()).data
    }
    private func path(_ id: UUID, part: Int) -> [String] { ["v1", "workspace", "backups", id.uuidString, "parts", String(part)] }
}

/// Account-scoped Postgres backups reuse the causal snapshot merge, including deletions and offline edits.
public actor WorkspaceCloudBackup {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let transport: any WorkspaceCloudBackupTransport
    private let logger = Logger(subsystem: "dev.blot.workspace", category: "cloud-backup")
    private var uploadedFingerprint: String?
    private var downloaded: Set<UUID> = []
    private var pending: (manifest: WorkspaceCloudBackupManifest, bytes: Data, fingerprint: String)?
    private var active: Task<Void, Error>?
    private var observer: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    private static let chunkBytes = 524_288
    private static let maximumBytes = 32 * 1024 * 1024

    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, transport: any WorkspaceCloudBackupTransport) {
        self.repository = repository; self.identity = identity; self.transport = transport
    }

    public func start() {
        guard observer == nil else { return }
        observer = Task { [weak self, repository] in
            for await _ in await repository.changes() {
                do {
                    try await Task.sleep(for: .seconds(2))
                    try Task.checkCancellation()
                    try await self?.synchronize()
                } catch is CancellationError { return }
                catch { await self?.reportFailure(error) }
            }
        }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await self?.synchronize()
                } catch is CancellationError { return }
                catch { await self?.reportFailure(error) }
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }

    public func stop() async {
        let workers = [observer, poller].compactMap { $0 }
        observer = nil; poller = nil
        for worker in workers { worker.cancel() }
        active?.cancel()
        for worker in workers { await worker.value }
        if let active { _ = await active.result }
        active = nil
    }

    /// Foreground refreshes are best-effort; failures are retained in diagnostics and retried.
    public func refresh() async {
        do { try await synchronize() }
        catch is CancellationError { return }
        catch { reportFailure(error) }
    }

    public func synchronize() async throws {
        if let active { return try await active.value }
        let worker = Task { try await self.performSync() }
        active = worker
        defer { active = nil }
        try await worker.value
    }

    private func performSync() async throws {
        // Receiving and sending are independent. A full upload quota or a failed local
        // snapshot must never prevent this device from receiving the account's chats.
        var failure: (any Error)?
        do { try await downloadSnapshots() }
        catch is CancellationError { throw CancellationError() }
        catch { failure = error }
        try Task.checkCancellation()
        do { try await uploadLatestSnapshot() }
        catch is CancellationError { throw CancellationError() }
        catch { if failure == nil { failure = error } }
        if let failure { throw failure }
    }

    private func uploadLatestSnapshot() async throws {
        // Finish an interrupted immutable upload before publishing newer local edits.
        if pending != nil { try await uploadPendingSnapshot() }
        try Task.checkCancellation()
        let snapshot = try await repository.replicaSnapshot(identity: identity)
        let fingerprint = try Self.fingerprint(snapshot)
        guard fingerprint != uploadedFingerprint, (!snapshot.records.isEmpty || !(snapshot.messagePins ?? []).isEmpty) else { return }
        let bytes = try WorkspaceCoding.encode(snapshot)
        guard bytes.count <= Self.maximumBytes else { throw WorkspaceSyncError.invalidSnapshot }
        pending = (.init(snapshotID: snapshot.id, deviceID: identity.deviceID, digest: Self.digest(bytes),
            byteCount: bytes.count, chunkCount: (bytes.count + Self.chunkBytes - 1) / Self.chunkBytes), bytes, fingerprint)
        try await uploadPendingSnapshot()
    }

    private func uploadPendingSnapshot() async throws {
        guard let pending else { return }
        try await transport.begin(pending.manifest)
        for part in 0..<pending.manifest.chunkCount {
            try Task.checkCancellation()
            let start = part * Self.chunkBytes
            let chunk = pending.bytes.subdata(in: start..<min(start + Self.chunkBytes, pending.bytes.count))
            try await transport.upload(snapshotID: pending.manifest.snapshotID, part: part, data: chunk)
        }
        try await transport.commit(snapshotID: pending.manifest.snapshotID)
        uploadedFingerprint = pending.fingerprint
        self.pending = nil
    }

    private func downloadSnapshots() async throws {
        try Task.checkCancellation()
        let manifests = try await transport.manifests()
        guard manifests.count <= 32 else { throw WorkspaceSyncError.invalidSnapshot }
        var failure: (any Error)?
        for manifest in manifests where manifest.deviceID != identity.deviceID && !downloaded.contains(manifest.snapshotID) {
            do {
                try await downloadSnapshot(manifest)
                downloaded.insert(manifest.snapshotID)
            } catch is CancellationError { throw CancellationError() }
            catch { if failure == nil { failure = error } }
        }
        downloaded.formIntersection(Set(manifests.map(\.snapshotID)))
        if let failure { throw failure }
    }

    private func downloadSnapshot(_ manifest: WorkspaceCloudBackupManifest) async throws {
        try Task.checkCancellation()
        guard manifest.byteCount > 0, manifest.byteCount <= Self.maximumBytes,
              manifest.chunkCount == (manifest.byteCount + Self.chunkBytes - 1) / Self.chunkBytes else {
            throw WorkspaceSyncError.invalidSnapshot
        }
        var bytes = Data()
        for part in 0..<manifest.chunkCount {
            try Task.checkCancellation()
            let chunk = try await transport.download(snapshotID: manifest.snapshotID, part: part)
            guard chunk.count == min(Self.chunkBytes, manifest.byteCount - part * Self.chunkBytes) else { throw WorkspaceSyncError.invalidSnapshot }
            bytes.append(chunk)
        }
        guard Self.digest(bytes) == manifest.digest else { throw WorkspaceSyncError.invalidSnapshot }
        let remote = try WorkspaceCoding.decode(WorkspaceReplicaSnapshot.self, from: bytes)
        guard remote.id == manifest.snapshotID else { throw WorkspaceSyncError.invalidSnapshot }
        try await repository.installReplicaSnapshot(remote, identity: identity)
    }

    private func reportFailure(_ error: any Error) {
        if case let WorkspaceCloudError.rejected(status, _) = error {
            logger.warning("Account synchronization will retry; HTTP status=\(status, privacy: .public)")
        } else {
            let failure = error as NSError
            logger.warning("Account synchronization will retry; domain=\(failure.domain, privacy: .public) code=\(failure.code)")
        }
    }
    private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private static func fingerprint(_ snapshot: WorkspaceReplicaSnapshot) throws -> String {
        struct Content: Encodable {
            let watermark: WorkspaceVersionVector
            let records: [WorkspaceReplicaRecord]
            let messagePins: [WorkspaceMessagePin]
        }
        let records = snapshot.records.sorted { $0.kind + $0.recordID.uuidString < $1.kind + $1.recordID.uuidString }
        return digest(try WorkspaceCoding.encode(Content(watermark: snapshot.watermark, records: records, messagePins: (snapshot.messagePins ?? []).sorted { $0.messageID.uuidString < $1.messageID.uuidString })))
    }
}
