import CryptoKit
import Foundation

public struct WorkspaceEncryptedPacket: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case change, snapshot }
    public let kind: Kind
    public let workspaceID: UUID
    public let originDeviceID: UUID
    public let changeID: UUID
    public let sequence: Int64
    public let keyEpoch: Int64
    public let ciphertext: Data
    public let signature: Data

    func headerBytes() -> Data {
        var data = Data("BLOT-APPLE-SYNC-1".utf8)
        data.append(kind == .change ? 1 : 2)
        for id in [workspaceID, originDeviceID, changeID] {
            var value = id.uuid
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        for number in [sequence, keyEpoch] {
            var value = number.bigEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}

/// Per-device signing keys and epoch keys belong in Keychain, never in the workspace records.
public actor WorkspaceSyncCryptography {
    private let identity: WorkspaceIdentity
    private let signingKey: P256.Signing.PrivateKey
    private let keys: [Int64: SymmetricKey]
    public nonisolated let currentEpoch: Int64

    public init(identity: WorkspaceIdentity, signingPrivateKey: Data, epochKeys: [Int64: Data], currentEpoch: Int64) throws {
        guard currentEpoch > 0, epochKeys[currentEpoch] != nil, epochKeys.allSatisfy({ $0.key > 0 && $0.value.count == 32 }) else {
            throw WorkspaceSyncError.unknownKeyEpoch
        }
        self.identity = identity
        self.signingKey = try P256.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
        self.keys = epochKeys.mapValues { SymmetricKey(data: $0) }
        self.currentEpoch = currentEpoch
    }

    public func publicSigningKey() -> Data { signingKey.publicKey.x963Representation }

    public func encrypt(_ change: WorkspaceSyncChange) throws -> WorkspaceEncryptedPacket {
        guard change.workspaceID == identity.workspaceID, change.ownerID == identity.ownerID,
              change.originDeviceID == identity.deviceID, change.sequence > 0 else { throw WorkspaceSyncError.identityMismatch }
        let data = try WorkspaceCoding.encode(change)
        guard data.count <= 512 * 1024 else { throw WorkspaceSyncError.invalidChange }
        return try seal(data, kind: .change, id: change.changeID, sequence: change.sequence)
    }

    public func encryptSnapshot(_ snapshot: WorkspaceReplicaSnapshot) throws -> WorkspaceEncryptedPacket {
        guard snapshot.workspaceID == identity.workspaceID, snapshot.ownerID == identity.ownerID else { throw WorkspaceSyncError.identityMismatch }
        let data = try WorkspaceCoding.encode(snapshot)
        guard data.count <= 128 * 1024 * 1024 else { throw WorkspaceSyncError.invalidSnapshot }
        return try seal(data, kind: .snapshot, id: snapshot.id, sequence: 0)
    }

    public func decrypt(_ packet: WorkspaceEncryptedPacket, trustedSigningKey: Data) throws -> WorkspaceSyncChange {
        guard packet.kind == .change, packet.sequence > 0 else { throw WorkspaceSyncError.invalidChange }
        let data = try open(packet, trustedSigningKey: trustedSigningKey)
        guard data.count <= 512 * 1024 else { throw WorkspaceSyncError.invalidChange }
        let change = try WorkspaceCoding.decode(WorkspaceSyncChange.self, from: data)
        guard change.workspaceID == packet.workspaceID, change.originDeviceID == packet.originDeviceID,
              change.changeID == packet.changeID, change.sequence == packet.sequence, change.ownerID == identity.ownerID else {
            throw WorkspaceSyncError.identityMismatch
        }
        return change
    }

    public func decryptSnapshot(_ packet: WorkspaceEncryptedPacket, trustedSigningKey: Data) throws -> WorkspaceReplicaSnapshot {
        guard packet.kind == .snapshot, packet.sequence == 0 else { throw WorkspaceSyncError.invalidSnapshot }
        let data = try open(packet, trustedSigningKey: trustedSigningKey)
        guard data.count <= 128 * 1024 * 1024 else { throw WorkspaceSyncError.invalidSnapshot }
        let snapshot = try WorkspaceCoding.decode(WorkspaceReplicaSnapshot.self, from: data)
        guard snapshot.workspaceID == identity.workspaceID, snapshot.ownerID == identity.ownerID, snapshot.id == packet.changeID else {
            throw WorkspaceSyncError.identityMismatch
        }
        return snapshot
    }

    private func seal(_ data: Data, kind: WorkspaceEncryptedPacket.Kind, id: UUID, sequence: Int64) throws -> WorkspaceEncryptedPacket {
        let header = WorkspaceEncryptedPacket(kind: kind, workspaceID: identity.workspaceID, originDeviceID: identity.deviceID,
            changeID: id, sequence: sequence, keyEpoch: currentEpoch, ciphertext: Data(), signature: Data())
        let key = try encryptionKey(header)
        let nonce: AES.GCM.Nonce
        if kind == .change {
            var number = sequence.bigEndian
            var bytes = Data(repeating: 0, count: 4)
            withUnsafeBytes(of: &number) { bytes.append(contentsOf: $0) }
            nonce = try AES.GCM.Nonce(data: bytes)
        } else { nonce = AES.GCM.Nonce() }
        let sealed = try AES.GCM.seal(data, using: key, nonce: nonce, authenticating: header.headerBytes())
        guard let ciphertext = sealed.combined else { throw WorkspaceSyncError.invalidChange }
        let signature = try signingKey.signature(for: header.headerBytes() + ciphertext).derRepresentation
        return WorkspaceEncryptedPacket(kind: kind, workspaceID: header.workspaceID, originDeviceID: header.originDeviceID,
            changeID: id, sequence: sequence, keyEpoch: currentEpoch, ciphertext: ciphertext, signature: signature)
    }

    private func open(_ packet: WorkspaceEncryptedPacket, trustedSigningKey: Data) throws -> Data {
        guard packet.workspaceID == identity.workspaceID, packet.keyEpoch > 0 else { throw WorkspaceSyncError.identityMismatch }
        let key = try P256.Signing.PublicKey(x963Representation: trustedSigningKey)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: packet.signature)
        guard key.isValidSignature(signature, for: packet.headerBytes() + packet.ciphertext) else { throw WorkspaceSyncError.invalidSignature }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: packet.ciphertext), using: encryptionKey(packet), authenticating: packet.headerBytes())
    }

    private func encryptionKey(_ packet: WorkspaceEncryptedPacket) throws -> SymmetricKey {
        guard let epochKey = keys[packet.keyEpoch] else { throw WorkspaceSyncError.unknownKeyEpoch }
        var info = Data("BLOT-APPLE-SYNC-AES-1".utf8)
        info.append(packet.headerBytes().dropLast(16))
        if packet.kind == .change {
            // Every change in a device/epoch shares a key; the durable sequence is its unique nonce.
            info = Data(("BLOT-APPLE-SYNC-CHANGE-1:" + packet.workspaceID.uuidString + ":" + packet.originDeviceID.uuidString).utf8)
        }
        var epoch = packet.keyEpoch.bigEndian
        withUnsafeBytes(of: &epoch) { info.append(contentsOf: $0) }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: epochKey, salt: Data("BLOT-APPLE-WORKSPACE".utf8), info: info, outputByteCount: 32)
    }

    func attachmentKey(_ descriptor: WorkspaceAttachmentDescriptor) throws -> SymmetricKey {
        guard descriptor.workspaceID == identity.workspaceID, let epochKey = keys[descriptor.keyEpoch] else { throw WorkspaceSyncError.unknownKeyEpoch }
        let info = Data(("BLOT-ATTACHMENT-KEY-1:" + descriptor.workspaceID.uuidString + ":" + descriptor.artifactID.uuidString + ":" + descriptor.hash).utf8)
            + WorkspaceDeviceKeys.integer(descriptor.keyEpoch)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: epochKey, salt: Data("BLOT-APPLE-WORKSPACE".utf8), info: info, outputByteCount: 32)
    }
}
