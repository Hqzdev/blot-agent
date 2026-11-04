import CryptoKit
import Foundation

/// A missing donor leaves a durable request. Only a complete signed snapshot can advance the cursor.
public actor WorkspaceSnapshotSync {
    private static let chunkBytes = 262_144
    private static let maximumBytes = 128 * 1024 * 1024
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let keys: WorkspaceDeviceKeys
    private let cryptography: WorkspaceSyncCryptography
    private let engine: WorkspaceSyncEngine
    private let transport: any WorkspaceSnapshotTransport
    private let blobs: any WorkspaceAttachmentTransport
    private let trust: any WorkspaceDeviceTrust
    private let cacheDirectory: URL
    private var fulfilling = false
    private var receiving: Set<UUID> = []

    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, keys: WorkspaceDeviceKeys,
                cryptography: WorkspaceSyncCryptography, engine: WorkspaceSyncEngine, transport: any WorkspaceSnapshotTransport,
                blobs: any WorkspaceAttachmentTransport, trust: any WorkspaceDeviceTrust, cacheDirectory: URL) {
        self.repository = repository; self.identity = identity; self.keys = keys; self.cryptography = cryptography
        self.engine = engine; self.transport = transport; self.blobs = blobs; self.trust = trust; self.cacheDirectory = cacheDirectory
    }

    public func request(commandID: UUID) async throws -> WorkspaceSnapshotStatus {
        let cursor = try await repository.snapshotRequestCursor(id: commandID)
        let status = try await transport.request(id: commandID, minimumCursor: cursor)
        guard status.request.requestID == commandID, status.request.requesterDeviceID == identity.deviceID,
              status.request.minimumCursor >= cursor else { throw WorkspaceSyncError.invalidSnapshot }
        return status
    }

    public func pendingRequests() async throws -> [UUID] { try await repository.pendingSnapshotRequestIDs() }

    public func fulfillPending() async throws {
        guard !fulfilling else { return }
        fulfilling = true
        defer { fulfilling = false }
        let pending = try await transport.pending()
        guard pending.count <= 50 else { throw WorkspaceSyncError.invalidSnapshot }
        guard !pending.isEmpty else { return }
        try await engine.synchronize()
        for request in pending {
            try Task.checkCancellation()
            guard request.requesterDeviceID != identity.deviceID, request.minimumCursor >= 0 else { throw WorkspaceSyncError.invalidSnapshot }
            let offer: WorkspaceSnapshotOffer
            let ciphertext: Data
            if let saved = try cachedOffer(request: request) {
                offer = saved.0; ciphertext = saved.1
            } else {
                let snapshot = try await repository.replicaSnapshot(identity: identity)
                guard snapshot.relayCursor >= request.minimumCursor else { throw WorkspaceSyncError.replayUnavailable }
                let packet = try await cryptography.encryptSnapshot(snapshot)
                guard packet.ciphertext.count <= Self.maximumBytes else { throw WorkspaceSyncError.invalidSnapshot }
                let unsigned = WorkspaceSnapshotOffer(requestID: request.requestID, snapshotID: packet.changeID,
                    donorDeviceID: identity.deviceID, keyEpoch: packet.keyEpoch, relayCursor: snapshot.relayCursor,
                    byteCount: packet.ciphertext.count, chunkCount: Self.chunkCount(packet.ciphertext.count),
                    digest: Self.digest(packet.ciphertext), packetSignature: packet.signature, signature: Data())
                offer = unsigned.signed(try await keys.signProof(domain: "BLOT-SNAPSHOT-OFFER-1",
                    ids: unsigned.proofIDs(workspaceID: identity.workspaceID), values: unsigned.proofValues))
                ciphertext = packet.ciphertext
                // Freeze both the ciphertext and its manifest before the first network request.
                let folder = try cacheURL(direction: "outgoing", id: request.requestID)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try ciphertext.write(to: folder.appendingPathComponent("ciphertext"), options: .atomic)
                try JSONEncoder().encode(offer).write(to: folder.appendingPathComponent("offer.json"), options: .atomic)
            }
            // Every local change represented by the snapshot must reach the relay before its offer.
            // The snapshot froze those versions, so later edits cannot replace their sequences.
            try await engine.synchronize()
            for index in 0..<offer.chunkCount {
                try Task.checkCancellation()
                let start = index * Self.chunkBytes, end = min(ciphertext.count, (index + 1) * Self.chunkBytes)
                try await blobs.put(.init(blobID: offer.snapshotID, index: index, count: offer.chunkCount, ciphertext: ciphertext.subdata(in: start..<end)))
            }
            try await transport.publish(offer)
            try? FileManager.default.removeItem(at: cacheURL(direction: "outgoing", id: request.requestID))
        }
    }

    /// Returns false while no trusted device has supplied a current snapshot.
    public func receive(requestID: UUID) async throws -> Bool {
        guard receiving.insert(requestID).inserted else { return false }
        defer { receiving.remove(requestID) }
        let status = try await transport.status(id: requestID)
        guard status.request.requestID == requestID, status.request.requesterDeviceID == identity.deviceID,
              status.request.minimumCursor >= 0 else { throw WorkspaceSyncError.invalidSnapshot }
        guard let offer = status.offer else { return false }
        try validate(offer)
        guard offer.requestID == requestID, offer.relayCursor >= status.request.minimumCursor else { throw WorkspaceSyncError.invalidSnapshot }
        let signingKey = try await trust.signingKey(for: offer.donorDeviceID, sequence: 0)
        try WorkspaceDeviceKeys.verifyProof(offer.signature, signingKey: signingKey, domain: "BLOT-SNAPSHOT-OFFER-1",
            ids: offer.proofIDs(workspaceID: identity.workspaceID), values: offer.proofValues)
        let folder = try cacheURL(direction: "incoming", id: offer.snapshotID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var ciphertext = Data()
        for index in 0..<offer.chunkCount {
            try Task.checkCancellation()
            let expected = min(Self.chunkBytes, offer.byteCount - index * Self.chunkBytes)
            let file = folder.appendingPathComponent(String(index))
            let part: Data
            if let saved = try read(file, maximum: Self.chunkBytes), saved.count == expected { part = saved }
            else {
                let chunk = try await blobs.get(blobID: offer.snapshotID, index: index)
                guard chunk.blobID == offer.snapshotID, chunk.index == index, chunk.count == offer.chunkCount,
                      chunk.ciphertext.count == expected else { throw WorkspaceSyncError.invalidSnapshot }
                part = chunk.ciphertext
                try part.write(to: file, options: .atomic)
            }
            ciphertext.append(part)
        }
        guard ciphertext.count == offer.byteCount, Self.digest(ciphertext) == offer.digest else {
            try? FileManager.default.removeItem(at: folder)
            throw WorkspaceSyncError.invalidSnapshot
        }
        try await engine.installSnapshot(offer.packet(workspaceID: identity.workspaceID, ciphertext: ciphertext), expectedRelayCursor: offer.relayCursor)
        try? FileManager.default.removeItem(at: folder)
        try await engine.synchronize()
        try await repository.completeSnapshotRequest(id: requestID)
        return true
    }

    private func cachedOffer(request: WorkspaceSnapshotRequest) throws -> (WorkspaceSnapshotOffer, Data)? {
        let folder = try cacheURL(direction: "outgoing", id: request.requestID)
        guard let metadata = try read(folder.appendingPathComponent("offer.json"), maximum: 16_384),
              let offer = try? JSONDecoder().decode(WorkspaceSnapshotOffer.self, from: metadata),
              offer.requestID == request.requestID, offer.donorDeviceID == identity.deviceID,
              offer.keyEpoch == cryptography.currentEpoch, offer.relayCursor >= request.minimumCursor,
              (try? validate(offer)) != nil,
              let ciphertext = try read(folder.appendingPathComponent("ciphertext"), maximum: Self.maximumBytes),
              ciphertext.count == offer.byteCount, Self.digest(ciphertext) == offer.digest else { return nil }
        return (offer, ciphertext)
    }
    private func validate(_ offer: WorkspaceSnapshotOffer) throws {
        guard offer.byteCount >= 28, offer.byteCount <= Self.maximumBytes, offer.keyEpoch > 0,
              offer.relayCursor >= 0, offer.chunkCount == Self.chunkCount(offer.byteCount),
              offer.digest.count == 64, offer.digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              (8...80).contains(offer.packetSignature.count), (8...80).contains(offer.signature.count) else {
            throw WorkspaceSyncError.invalidSnapshot
        }
    }
    private static func chunkCount(_ bytes: Int) -> Int { (bytes + chunkBytes - 1) / chunkBytes }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func cacheURL(direction: String, id: UUID) throws -> URL {
        let root = cacheDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let result = root.appendingPathComponent(direction).appendingPathComponent(id.uuidString).standardizedFileURL.resolvingSymlinksInPath()
        guard result.path.hasPrefix(root.path + "/") else { throw WorkspaceFileError.unsafePath }
        return result
    }
    private func read(_ url: URL, maximum: Int) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: maximum + 1), data.count <= maximum else { return nil }
        return data
    }
}
