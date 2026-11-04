import Foundation

public struct WorkspaceRelayDelivery: Codable, Equatable, Sendable {
    public let sequence: Int64
    public let packet: WorkspaceEncryptedPacket
    public init(sequence: Int64, packet: WorkspaceEncryptedPacket) { self.sequence = sequence; self.packet = packet }
}

public struct WorkspaceRelayBatch: Codable, Equatable, Sendable {
    public let deliveries: [WorkspaceRelayDelivery]
    public let cursor: Int64
    public let hasMore: Bool
    public init(deliveries: [WorkspaceRelayDelivery], cursor: Int64, hasMore: Bool) {
        self.deliveries = deliveries; self.cursor = cursor; self.hasMore = hasMore
    }
}

public protocol WorkspaceSyncTransport: Sendable {
    /// True means the ciphertext was durably accepted by the relay, including after a lost HTTP response.
    func hasAccepted(changeID: UUID) async throws -> Bool
    func upload(_ packet: WorkspaceEncryptedPacket) async throws -> UUID
    func pull(after cursor: Int64, limit: Int) async throws -> WorkspaceRelayBatch
    func acknowledge(upTo cursor: Int64) async throws
}

public protocol WorkspaceDeviceTrust: Sendable {
    func signingKey(for deviceID: UUID, sequence: Int64) async throws -> Data
}

/// Transfers ciphertext only. A pull batch's records, inbox and cursor commit before its ACK.
public actor WorkspaceSyncEngine {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let cryptography: WorkspaceSyncCryptography
    private let transport: any WorkspaceSyncTransport
    private let trust: any WorkspaceDeviceTrust
    private var synchronizing = false

    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, cryptography: WorkspaceSyncCryptography,
                transport: any WorkspaceSyncTransport, trust: any WorkspaceDeviceTrust) {
        self.repository = repository; self.identity = identity; self.cryptography = cryptography
        self.transport = transport; self.trust = trust
    }

    public func synchronize() async throws {
        guard !synchronizing else { return }
        synchronizing = true
        defer { synchronizing = false }
        // Repeat a lost ACK even when no new deliveries arrive.
        try await transport.acknowledge(upTo: repository.relayCursor())
        while true {
            let changes = try await repository.claimSyncChanges(limit: 50)
            if changes.isEmpty { break }
            for change in changes {
                try Task.checkCancellation()
                let cached = try await repository.encryptedOutboxPacket(changeID: change.changeID)
                if let cached, cached.keyEpoch != cryptography.currentEpoch,
                   try await transport.hasAccepted(changeID: change.changeID) {
                    try await repository.acknowledgeOutbox([change.changeID])
                    continue
                }
                let packet: WorkspaceEncryptedPacket
                if let cached, cached.keyEpoch == cryptography.currentEpoch { packet = cached }
                else {
                    packet = try await repository.cacheEncryptedOutboxPacket(cryptography.encrypt(change))
                }
                guard try await transport.upload(packet) == change.changeID else { throw WorkspaceSyncError.replayConflict }
                try await repository.acknowledgeOutbox([change.changeID])
            }
        }
        for _ in 0..<1_000 {
            try Task.checkCancellation()
            let cursor = try await repository.relayCursor()
            let batch = try await transport.pull(after: cursor, limit: 50)
            guard batch.cursor >= cursor, batch.deliveries.count <= 50 else { throw WorkspaceSyncError.invalidChange }
            var previous = cursor
            var changes: [WorkspaceSyncChange] = []
            for delivery in batch.deliveries {
                guard delivery.sequence > previous, delivery.sequence <= batch.cursor else { throw WorkspaceSyncError.sequenceGap }
                previous = delivery.sequence
                let key = try await trust.signingKey(for: delivery.packet.originDeviceID, sequence: delivery.packet.sequence)
                changes.append(try await cryptography.decrypt(delivery.packet, trustedSigningKey: key))
            }
            guard !batch.hasMore || batch.cursor > cursor else { throw WorkspaceSyncError.sequenceGap }
            try await repository.applySyncChanges(changes, identity: identity, relayCursor: batch.cursor)
            try await transport.acknowledge(upTo: batch.cursor)
            if !batch.hasMore { return }
        }
    }

    public func installSnapshot(_ packet: WorkspaceEncryptedPacket, expectedRelayCursor: Int64? = nil) async throws {
        let key = try await trust.signingKey(for: packet.originDeviceID, sequence: packet.sequence)
        let snapshot = try await cryptography.decryptSnapshot(packet, trustedSigningKey: key)
        if let expectedRelayCursor, snapshot.relayCursor != expectedRelayCursor { throw WorkspaceSyncError.invalidSnapshot }
        try await repository.installReplicaSnapshot(snapshot, identity: identity)
        try await transport.acknowledge(upTo: repository.relayCursor())
    }
}
