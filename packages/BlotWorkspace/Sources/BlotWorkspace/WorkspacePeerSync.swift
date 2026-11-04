import Foundation

public struct WorkspacePeerCapabilities: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public let recordKinds: [String]
    public let maximumFrameBytes: Int
    public init() {
        schemaVersion = 3; revision = 2
        recordKinds = WorkspaceRecordCodec.supportedKinds.sorted()
        maximumFrameBytes = 128 * 1024 * 1024
    }
    public func requireCompatible(_ peer: Self) throws {
        guard peer.schemaVersion == schemaVersion, peer.revision >= revision,
              Set(recordKinds).isSubset(of: Set(peer.recordKinds)), peer.maximumFrameBytes >= 1_048_576 else {
            throw WorkspaceSyncError.unsupportedRecord
        }
    }
}

public struct WorkspacePeerHello: Codable, Equatable, Sendable {
    public let senderID: UUID
    public let recipientID: UUID
    public let workspaceID: UUID
    public let challenge: UUID
    public let capabilities: WorkspacePeerCapabilities
    public let signature: Data
}

public struct WorkspacePeerReceipt: Codable, Equatable, Sendable {
    public let snapshotID: UUID
    public let senderID: UUID
    public let recipientID: UUID
    public let workspaceID: UUID
    public let signature: Data
}

/// Direct device-to-device replication. The caller supplies Wi-Fi or Bluetooth framing; there is no relay or execution handoff.
public actor WorkspacePeerSync {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let keys: WorkspaceDeviceKeys
    private let trust: any WorkspaceDeviceTrust
    private var challenges: [UUID: UUID] = [:]
    private var authorized: Set<UUID> = []
    private var outstanding: [UUID: UUID] = [:]
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, keys: WorkspaceDeviceKeys, trust: any WorkspaceDeviceTrust) {
        self.repository = repository; self.identity = identity; self.keys = keys; self.trust = trust
    }
    public func challenge(peerID: UUID) throws -> UUID {
        guard peerID != identity.deviceID, challenges.count < 16 else { throw WorkspaceSyncError.identityMismatch }
        let nonce = UUID(); challenges[peerID] = nonce; authorized.remove(peerID)
        return nonce
    }
    public func hello(recipientID: UUID, challenge: UUID) async throws -> WorkspacePeerHello {
        _ = try await trust.signingKey(for: recipientID, sequence: 0)
        let capabilities = WorkspacePeerCapabilities()
        let signature = try await keys.signProof(domain: "BLOT-PEER-HELLO-2",
            ids: [identity.workspaceID, identity.deviceID, recipientID, challenge], values: [try WorkspaceCoding.encode(capabilities)])
        return .init(senderID: identity.deviceID, recipientID: recipientID, workspaceID: identity.workspaceID,
            challenge: challenge, capabilities: capabilities, signature: signature)
    }
    public func accept(_ hello: WorkspacePeerHello) async throws {
        guard hello.workspaceID == identity.workspaceID, hello.recipientID == identity.deviceID,
              challenges[hello.senderID] == hello.challenge else { throw WorkspaceSyncError.identityMismatch }
        try WorkspacePeerCapabilities().requireCompatible(hello.capabilities)
        let publicKey = try await trust.signingKey(for: hello.senderID, sequence: 0)
        try WorkspaceDeviceKeys.verifyProof(hello.signature, signingKey: publicKey, domain: "BLOT-PEER-HELLO-2",
            ids: [identity.workspaceID, hello.senderID, hello.recipientID, hello.challenge], values: [try WorkspaceCoding.encode(hello.capabilities)])
        challenges[hello.senderID] = nil; authorized.insert(hello.senderID)
    }
    public func snapshot(for peerID: UUID) async throws -> WorkspaceEncryptedPacket {
        guard authorized.contains(peerID), outstanding.count < 16 else { throw WorkspaceStorageError.permissionDenied }
        let snapshot = try await repository.replicaSnapshot(identity: identity)
        let packet = try await keys.cryptography().encryptSnapshot(snapshot)
        guard packet.ciphertext.count <= WorkspacePeerCapabilities().maximumFrameBytes else { throw WorkspaceSyncError.invalidSnapshot }
        outstanding[packet.changeID] = peerID
        return packet
    }
    public func receive(_ packet: WorkspaceEncryptedPacket, from peerID: UUID) async throws -> WorkspacePeerReceipt {
        guard authorized.contains(peerID), packet.originDeviceID == peerID, packet.workspaceID == identity.workspaceID,
              packet.kind == .snapshot, packet.ciphertext.count <= WorkspacePeerCapabilities().maximumFrameBytes else {
            throw WorkspaceStorageError.permissionDenied
        }
        let publicKey = try await trust.signingKey(for: peerID, sequence: 0)
        let snapshot = try await keys.cryptography().decryptSnapshot(packet, trustedSigningKey: publicKey)
        // Existing snapshot merge preserves pending local edits and tombstones. It never starts imported tasks.
        try await repository.installReplicaSnapshot(snapshot, identity: identity)
        let signature = try await keys.signProof(domain: "BLOT-PEER-ACK-2",
            ids: [identity.workspaceID, packet.changeID, identity.deviceID, peerID], values: [])
        return .init(snapshotID: packet.changeID, senderID: identity.deviceID, recipientID: peerID,
            workspaceID: identity.workspaceID, signature: signature)
    }
    public func acknowledge(_ receipt: WorkspacePeerReceipt) async throws {
        guard authorized.contains(receipt.senderID), receipt.workspaceID == identity.workspaceID,
              receipt.recipientID == identity.deviceID, outstanding[receipt.snapshotID] == receipt.senderID else {
            throw WorkspaceSyncError.identityMismatch
        }
        let key = try await trust.signingKey(for: receipt.senderID, sequence: 0)
        try WorkspaceDeviceKeys.verifyProof(receipt.signature, signingKey: key, domain: "BLOT-PEER-ACK-2",
            ids: [identity.workspaceID, receipt.snapshotID, receipt.senderID, receipt.recipientID], values: [])
        outstanding[receipt.snapshotID] = nil
        // Peer receipts do not globally clear outbox: another paired device may still need these changes.
    }
    public func disconnect(peerID: UUID) {
        authorized.remove(peerID); challenges[peerID] = nil
        outstanding = outstanding.filter { $0.value != peerID }
    }
}
