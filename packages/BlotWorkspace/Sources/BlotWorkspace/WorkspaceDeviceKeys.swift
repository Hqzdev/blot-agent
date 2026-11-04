import CryptoKit
import Foundation

public struct WorkspaceDevicePublicKeys: Codable, Equatable, Sendable {
    public let signingKey: Data
    public let encryptionKey: Data
}

/// Signing, agreement and history keys are separate and persist only in the device credential store.
public actor WorkspaceDeviceKeys {
    private struct Material: Codable {
        let signing: Data
        let agreement: Data
        var epochKeys: [Int64: Data]
        var currentEpoch: Int64?
    }
    private struct KeyRing: Codable {
        let currentEpoch: Int64
        let keys: [Int64: Data]
        let trustedDevices: [UUID: WorkspaceDevicePublicKeys]?
    }
    private struct Envelope: Codable {
        let workspaceID: UUID
        let signerID: UUID
        let recipientID: UUID
        let epoch: Int64
        let ephemeralKey: Data
        let ciphertext: Data
    }
    public let identity: WorkspaceIdentity
    private let credentials: any WorkspaceCredentialStore
    private let name: String
    private var material: Material
    private var pendingWrite: Task<Void, Error>?

    private init(identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore, name: String, material: Material) {
        self.identity = identity; self.credentials = credentials; self.name = name; self.material = material
    }
    public static func open(identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore) async throws -> WorkspaceDeviceKeys {
        let name = "device-keys:" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString
        let material: Material
        if let saved = try await credentials.read(name) {
            material = try JSONDecoder().decode(Material.self, from: saved)
            _ = try P256.Signing.PrivateKey(rawRepresentation: material.signing)
            _ = try P256.KeyAgreement.PrivateKey(rawRepresentation: material.agreement)
            guard material.epochKeys.allSatisfy({ $0.key > 0 && $0.value.count == 32 }),
                  material.currentEpoch.map({ material.epochKeys[$0] != nil }) ?? material.epochKeys.isEmpty else { throw WorkspaceSyncError.unknownKeyEpoch }
        } else {
            material = Material(signing: P256.Signing.PrivateKey().rawRepresentation,
                agreement: P256.KeyAgreement.PrivateKey().rawRepresentation, epochKeys: [:], currentEpoch: nil)
            try await credentials.write(JSONEncoder().encode(material), name: name)
        }
        return WorkspaceDeviceKeys(identity: identity, credentials: credentials, name: name, material: material)
    }
    public func publicKeys() throws -> WorkspaceDevicePublicKeys {
        try .init(signingKey: P256.Signing.PrivateKey(rawRepresentation: material.signing).publicKey.x963Representation,
                  encryptionKey: P256.KeyAgreement.PrivateKey(rawRepresentation: material.agreement).publicKey.x963Representation)
    }
    public func initializeWorkspace() async throws {
        if let pendingWrite { _ = try? await pendingWrite.value }
        guard material.currentEpoch == nil, material.epochKeys.isEmpty else { return }
        var next = material
        next.currentEpoch = 1
        next.epochKeys[1] = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try await save(next)
    }
    public func cryptography() throws -> WorkspaceSyncCryptography {
        guard let epoch = material.currentEpoch else { throw WorkspaceSyncError.unknownKeyEpoch }
        return try WorkspaceSyncCryptography(identity: identity, signingPrivateKey: material.signing, epochKeys: material.epochKeys, currentEpoch: epoch)
    }
    public func currentEpoch() throws -> Int64 {
        guard let epoch = material.currentEpoch else { throw WorkspaceSyncError.unknownKeyEpoch }
        return epoch
    }
    public func signProof(domain: String, ids: [UUID], values: [Data]) throws -> Data {
        try P256.Signing.PrivateKey(rawRepresentation: material.signing).signature(for: Self.proofMessage(domain: domain, ids: ids, values: values)).derRepresentation
    }
    public nonisolated static func verifyProof(_ signature: Data, signingKey: Data, domain: String, ids: [UUID], values: [Data]) throws {
        let key = try P256.Signing.PublicKey(x963Representation: signingKey)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signature)
        guard key.isValidSignature(signature, for: proofMessage(domain: domain, ids: ids, values: values)) else { throw WorkspaceSyncError.invalidSignature }
    }
    public func prepareNextKeyEpoch() async throws -> Int64 {
        if let pendingWrite { _ = try? await pendingWrite.value }
        guard let current = material.currentEpoch, current < Int64.max else { throw WorkspaceSyncError.unknownKeyEpoch }
        let epoch = current + 1
        if material.epochKeys[epoch] != nil { return epoch }
        var next = material
        next.epochKeys[epoch] = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try await save(next)
        return epoch
    }
    public func activateKeyEpoch(_ epoch: Int64) async throws {
        if let pendingWrite { _ = try? await pendingWrite.value }
        guard epoch >= (material.currentEpoch ?? 0), material.epochKeys[epoch] != nil else { throw WorkspaceSyncError.unknownKeyEpoch }
        var next = material; next.currentEpoch = epoch
        try await save(next)
    }
    public func wrapKeys(for recipientID: UUID, encryptionKey: Data, epoch requestedEpoch: Int64? = nil,
                         trustedDevices: [UUID: WorkspaceDevicePublicKeys] = [:]) throws -> Data {
        guard let current = material.currentEpoch else { throw WorkspaceSyncError.unknownKeyEpoch }
        let epoch = requestedEpoch ?? current
        guard epoch >= current, material.epochKeys[epoch] != nil else { throw WorkspaceSyncError.unknownKeyEpoch }
        let recipient = try P256.KeyAgreement.PublicKey(x963Representation: encryptionKey)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let publicKey = ephemeral.publicKey.x963Representation
        let header = Self.grantHeader(workspaceID: identity.workspaceID, signerID: identity.deviceID, recipientID: recipientID, epoch: epoch, ephemeralKey: publicKey)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("BLOT-DEVICE-KEY-GRANT-1".utf8), sharedInfo: header, outputByteCount: 32)
        let ring = KeyRing(currentEpoch: epoch, keys: material.epochKeys.filter { $0.key <= epoch }, trustedDevices: trustedDevices)
        let sealed = try AES.GCM.seal(JSONEncoder().encode(ring), using: key, authenticating: header)
        guard let ciphertext = sealed.combined else { throw WorkspaceSyncError.invalidChange }
        return try JSONEncoder().encode(Envelope(workspaceID: identity.workspaceID, signerID: identity.deviceID,
            recipientID: recipientID, epoch: epoch, ephemeralKey: publicKey, ciphertext: ciphertext))
    }
    /// Caller first verifies the owner's signature over the exact wrapped bytes and recipient keys.
    @discardableResult
    public func acceptWrappedKeys(_ bytes: Data, signerID: UUID, epoch: Int64) async throws -> [UUID: WorkspaceDevicePublicKeys] {
        if let pendingWrite { _ = try? await pendingWrite.value }
        guard bytes.count <= 131_072 else { throw WorkspaceSyncError.invalidChange }
        let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard envelope.workspaceID == identity.workspaceID, envelope.recipientID == identity.deviceID,
              envelope.signerID == signerID, envelope.epoch == epoch, epoch >= (material.currentEpoch ?? 0) else { throw WorkspaceSyncError.identityMismatch }
        let ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: envelope.ephemeralKey)
        let agreement = try P256.KeyAgreement.PrivateKey(rawRepresentation: material.agreement)
        let shared = try agreement.sharedSecretFromKeyAgreement(with: ephemeral)
        let header = Self.grantHeader(workspaceID: identity.workspaceID, signerID: signerID, recipientID: identity.deviceID, epoch: epoch, ephemeralKey: envelope.ephemeralKey)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("BLOT-DEVICE-KEY-GRANT-1".utf8), sharedInfo: header, outputByteCount: 32)
        let data = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.ciphertext), using: key, authenticating: header)
        let ring = try JSONDecoder().decode(KeyRing.self, from: data)
        guard ring.currentEpoch == epoch, ring.keys[epoch] != nil, ring.keys.count <= 4096,
              ring.keys.allSatisfy({ $0.key > 0 && $0.key <= epoch && $0.value.count == 32 }),
              (ring.trustedDevices?.count ?? 0) <= 4096 else { throw WorkspaceSyncError.unknownKeyEpoch }
        for publicKeys in ring.trustedDevices?.values ?? Dictionary<UUID, WorkspaceDevicePublicKeys>().values {
            _ = try P256.Signing.PublicKey(x963Representation: publicKeys.signingKey)
            _ = try P256.KeyAgreement.PublicKey(x963Representation: publicKeys.encryptionKey)
        }
        for (known, value) in material.epochKeys where known <= (material.currentEpoch ?? 0) {
            guard ring.keys[known] == nil || ring.keys[known] == value else { throw WorkspaceSyncError.unknownKeyEpoch }
        }
        var next = material
        next.currentEpoch = epoch
        next.epochKeys.merge(ring.keys, uniquingKeysWith: { _, new in new })
        try await save(next)
        return ring.trustedDevices ?? [:]
    }
    private func save(_ next: Material) async throws {
        let previous = pendingWrite
        let worker = Task {
            if let previous { _ = try? await previous.value }
            try await self.persist(next)
        }
        pendingWrite = worker
        try await worker.value
    }
    private func persist(_ next: Material) async throws {
        guard (next.currentEpoch ?? 0) >= (material.currentEpoch ?? 0), material.epochKeys.allSatisfy({
            $0.key > (material.currentEpoch ?? 0) || next.epochKeys[$0.key] == $0.value
        }) else {
            throw WorkspaceSyncError.unknownKeyEpoch
        }
        try await credentials.write(JSONEncoder().encode(next), name: name)
        material = next
    }
    private nonisolated static func grantHeader(workspaceID: UUID, signerID: UUID, recipientID: UUID, epoch: Int64, ephemeralKey: Data) -> Data {
        proofMessage(domain: "BLOT-DEVICE-KEY-GRANT-1", ids: [workspaceID, signerID, recipientID], values: [integer(epoch), ephemeralKey])
    }
    public nonisolated static func integer(_ value: Int64) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    private nonisolated static func proofMessage(domain: String, ids: [UUID], values: [Data]) -> Data {
        var result = Data(domain.utf8); result.append(0)
        for id in ids { var raw = id.uuid; withUnsafeBytes(of: &raw) { result.append(contentsOf: $0) } }
        for value in values {
            var count = UInt32(value.count).bigEndian
            withUnsafeBytes(of: &count) { result.append(contentsOf: $0) }
            result.append(value)
        }
        return result
    }
}
