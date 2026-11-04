import CryptoKit
import Foundation

public struct WorkspacePairingInvite: Codable, Equatable, Sendable {
    public let id: UUID
    public let workspaceID: UUID
    public let initiatorID: UUID
    public let secret: String
    public let initiatorSigningKey: Data
    public let initiatorEncryptionKey: Data
    public let expiresAt: String
}
public struct WorkspaceDeviceCertificate: Codable, Equatable, Sendable {
    public let workspaceID: UUID
    public let pairingID: UUID
    public let signerID: UUID
    public let epoch: Int64
    public let wrappedKeys: Data
    public let signature: Data
}
public struct WorkspaceCloudDevice: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: String
    public let signingKey: Data
    public let encryptionKey: Data
    public let revoked: Bool
    public let certificate: WorkspaceDeviceCertificate?
}
public struct WorkspacePairingStatus: Codable, Equatable, Sendable {
    public let id: UUID
    public let state: String
    public let candidate: WorkspaceCloudDevice?
    public let expiresAt: String
}
private struct DeviceRegistration: Encodable {
    let id: UUID
    let name: String
    let kind: String
    let signingKey: Data
    let encryptionKey: Data
    let signature: Data
}
private struct PairingApproval: Codable, Sendable {
    let deviceID: UUID
    let epoch: Int64
    let wrappedKeys: Data
    let signerID: UUID
    let signature: Data
}

/// Pins signing keys through local bootstrap or the QR owner's signed approval, never a bare server list.
public actor WorkspaceCloudDevices: WorkspaceDeviceTrust {
    private let http: WorkspaceCloudHTTP
    private let session: WorkspaceCloudSession
    private let keys: WorkspaceDeviceKeys
    private let credentials: any WorkspaceCredentialStore
    private let identity: WorkspaceIdentity
    private let trustName: String
    private var trusted: [UUID: WorkspaceDevicePublicKeys] = [:]
    private var pendingTrust: Task<Void, Error>?

    public init(http: WorkspaceCloudHTTP, session: WorkspaceCloudSession, keys: WorkspaceDeviceKeys,
                credentials: any WorkspaceCredentialStore, identity: WorkspaceIdentity) {
        self.http = http; self.session = session; self.keys = keys; self.credentials = credentials; self.identity = identity
        self.trustName = "device-trust-v2:" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString
    }
    public func restoreTrust() async throws {
        if let data = try await credentials.read(trustName) {
            let saved = try JSONDecoder().decode([UUID: WorkspaceDevicePublicKeys].self, from: data)
            for key in saved.values {
                _ = try P256.Signing.PublicKey(x963Representation: key.signingKey)
                _ = try P256.KeyAgreement.PublicKey(x963Representation: key.encryptionKey)
            }
            trusted = saved
        }
    }
    public func signingKey(for deviceID: UUID, sequence: Int64) async throws -> Data {
        if let pendingTrust { try await pendingTrust.value }
        guard sequence >= 0, let value = trusted[deviceID] else { throw WorkspaceSyncError.invalidSignature }
        return value.signingKey
    }
    public func bootstrap(name: String, kind: String) async throws {
        let current = try await account()
        guard current.bootstrapAllowed == true || current.deviceID == identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
        try await keys.initializeWorkspace()
        let publicKeys = try await keys.publicKeys()
        let signature = try await keys.signProof(domain: "BLOT-DEVICE-BOOTSTRAP-1",
            ids: [current.sessionID, identity.workspaceID, identity.deviceID], values: [publicKeys.signingKey, publicKeys.encryptionKey])
        let registration = DeviceRegistration(id: identity.deviceID, name: name, kind: kind, signingKey: publicKeys.signingKey,
            encryptionKey: publicKeys.encryptionKey, signature: signature)
        let result: WorkspaceCloudDevice
        do {
            result = try await http.request(WorkspaceCloudDevice.self, method: "POST", path: ["v1", "devices", "bootstrap"],
                body: JSONEncoder().encode(registration), accessToken: session.accessToken())
        } catch WorkspaceCloudError.rejected(status: 403, code: "device_pairing_required") {
            // A previous bootstrap may have committed before its HTTP response was lost.
            try await bindExistingSession()
            return
        }
        guard result.id == identity.deviceID, result.signingKey == publicKeys.signingKey,
              result.encryptionKey == publicKeys.encryptionKey else { throw WorkspaceSyncError.identityMismatch }
        try await remember([identity.deviceID: publicKeys])
        _ = try await session.refreshDeviceBinding()
    }
    public func bindExistingSession() async throws {
        let current = try await account()
        struct Challenge: Decodable, Sendable { let nonce: String; let expiresAt: String }
        let challenge = try await http.request(Challenge.self, method: "POST", path: ["v1", "auth", "device-challenge"], accessToken: session.accessToken())
        let signature = try await keys.signProof(domain: "BLOT-SESSION-BIND-1", ids: [current.sessionID, identity.deviceID], values: [Data(challenge.nonce.utf8)])
        struct Binding: Encodable { let deviceID: UUID; let nonce: String; let signature: Data }
        try await http.empty(method: "POST", path: ["v1", "auth", "device-bind"],
            body: JSONEncoder().encode(Binding(deviceID: identity.deviceID, nonce: challenge.nonce, signature: signature)), accessToken: session.accessToken())
        try await remember([identity.deviceID: keys.publicKeys()])
        _ = try await session.refreshDeviceBinding()
    }
    public func createInvite() async throws -> WorkspacePairingInvite {
        _ = try await account()
        let invite = try await http.request(WorkspacePairingInvite.self, method: "POST", path: ["v1", "devices", "pairings"], accessToken: session.accessToken())
        guard invite.workspaceID == identity.workspaceID, invite.initiatorID == identity.deviceID,
              try await keys.publicKeys().signingKey == invite.initiatorSigningKey,
              try await keys.publicKeys().encryptionKey == invite.initiatorEncryptionKey else { throw WorkspaceSyncError.identityMismatch }
        return invite
    }
    public func claim(_ invite: WorkspacePairingInvite, name: String, kind: String) async throws -> WorkspacePairingStatus {
        _ = try await account()
        try validate(invite)
        let publicKeys = try await keys.publicKeys()
        let signature = try await keys.signProof(domain: "BLOT-PAIR-CLAIM-1", ids: [identity.workspaceID, invite.id, identity.deviceID],
            values: [publicKeys.signingKey, publicKeys.encryptionKey, Data(invite.secret.utf8)])
        let registration = DeviceRegistration(id: identity.deviceID, name: name, kind: kind, signingKey: publicKeys.signingKey,
            encryptionKey: publicKeys.encryptionKey, signature: signature)
        struct Claim: Encodable { let pairingID: UUID; let secret: String; let device: DeviceRegistration }
        return try await http.request(WorkspacePairingStatus.self, method: "POST", path: ["v1", "devices", "pairings", "claim"],
            body: JSONEncoder().encode(Claim(pairingID: invite.id, secret: invite.secret, device: registration)), accessToken: session.accessToken())
    }
    public func inspect(_ invite: WorkspacePairingInvite) async throws -> WorkspacePairingStatus {
        try validate(invite, requireUnexpired: false)
        guard invite.initiatorID == identity.deviceID else { throw WorkspaceSyncError.identityMismatch }
        return try await http.request(WorkspacePairingStatus.self, method: "GET", path: ["v1", "devices", "pairings", invite.id.uuidString], accessToken: session.accessToken())
    }
    /// The UI supplies the code the owner explicitly confirmed after comparing both device displays.
    public func approve(_ invite: WorkspacePairingInvite, candidateID: UUID, confirmedCode: String) async throws {
        let status = try await inspect(invite)
        guard ["WAITING_CONFIRMATION", "APPROVED"].contains(status.state), let candidate = status.candidate, candidate.id == candidateID,
              confirmationCode(invite: invite, candidate: candidate) == confirmedCode else { throw WorkspaceStorageError.permissionDenied }
        struct Approval: Codable { let pairingID: UUID; let candidateID: UUID; let epoch: Int64; let wrappedKeys: Data; let signature: Data }
        let pendingName = trustName + ":approval:" + invite.id.uuidString
        let preparation: Approval
        if let saved = try await credentials.read(pendingName) {
            preparation = try JSONDecoder().decode(Approval.self, from: saved)
            guard preparation.pairingID == invite.id, preparation.candidateID == candidateID else { throw WorkspaceSyncError.identityMismatch }
        } else {
            try validate(invite)
            guard status.state == "WAITING_CONFIRMATION" else { throw WorkspaceStorageError.permissionDenied }
            let epoch = try await keys.currentEpoch()
            let wrapped = try await keys.wrapKeys(for: candidateID, encryptionKey: candidate.encryptionKey, trustedDevices: trusted)
            let signature = try await keys.signProof(domain: "BLOT-PAIR-APPROVE-1",
                ids: [identity.workspaceID, invite.id, identity.deviceID, candidateID],
                values: [WorkspaceDeviceKeys.integer(epoch), candidate.signingKey, candidate.encryptionKey, wrapped])
            preparation = Approval(pairingID: invite.id, candidateID: candidateID, epoch: epoch, wrappedKeys: wrapped, signature: signature)
            try await credentials.write(JSONEncoder().encode(preparation), name: pendingName)
        }
        let result = try await http.request(PairingApproval.self, method: "POST", path: ["v1", "devices", "pairings", "approve"],
            body: JSONEncoder().encode(preparation), accessToken: session.accessToken())
        guard result.deviceID == candidateID, result.wrappedKeys == preparation.wrappedKeys, result.signature == preparation.signature else { throw WorkspaceSyncError.invalidSignature }
        try await remember([candidateID: WorkspaceDevicePublicKeys(signingKey: candidate.signingKey, encryptionKey: candidate.encryptionKey)])
    }
    public func finishPairing(_ invite: WorkspacePairingInvite) async throws {
        try validate(invite, requireUnexpired: false)
        let result = try await http.request(PairingApproval.self, method: "GET", path: ["v1", "devices", "pairings", invite.id.uuidString, "result"], accessToken: session.accessToken())
        guard result.deviceID == identity.deviceID, result.signerID == invite.initiatorID else { throw WorkspaceSyncError.identityMismatch }
        let publicKeys = try await keys.publicKeys()
        try WorkspaceDeviceKeys.verifyProof(result.signature, signingKey: invite.initiatorSigningKey, domain: "BLOT-PAIR-APPROVE-1",
            ids: [identity.workspaceID, invite.id, invite.initiatorID, identity.deviceID],
            values: [WorkspaceDeviceKeys.integer(result.epoch), publicKeys.signingKey, publicKeys.encryptionKey, result.wrappedKeys])
        let inherited = try await keys.acceptWrappedKeys(result.wrappedKeys, signerID: result.signerID, epoch: result.epoch)
        try await remember(inherited)
        try await remember([identity.deviceID: publicKeys, invite.initiatorID: WorkspaceDevicePublicKeys(signingKey: invite.initiatorSigningKey, encryptionKey: invite.initiatorEncryptionKey)])
        _ = try await session.refreshDeviceBinding()
    }
    public nonisolated func confirmationCode(invite: WorkspacePairingInvite, candidate: WorkspaceCloudDevice) -> String {
        let bytes = Data("BLOT-PAIR-CODE-1:".utf8) + Data(invite.workspaceID.uuidString.utf8) + Data(invite.id.uuidString.utf8) + Data(invite.secret.utf8) +
            invite.initiatorSigningKey + invite.initiatorEncryptionKey +
            Data(candidate.id.uuidString.utf8) + candidate.signingKey + candidate.encryptionKey
        let digest = Array(SHA256.hash(data: bytes))
        let number = (UInt32(digest[0]) << 24) | (UInt32(digest[1]) << 16) | (UInt32(digest[2]) << 8) | UInt32(digest[3])
        return String(format: "%06u", number % 1_000_000)
    }
    public func candidateForConfirmation(name: String, kind: String) async throws -> WorkspaceCloudDevice {
        let value = try await keys.publicKeys()
        return WorkspaceCloudDevice(id: identity.deviceID, name: name, kind: kind, signingKey: value.signingKey, encryptionKey: value.encryptionKey, revoked: false, certificate: nil)
    }
    public func refreshDeviceTrust() async throws -> [WorkspaceCloudDevice] {
        if let pendingTrust { try await pendingTrust.value }
        let devices = try await http.request([WorkspaceCloudDevice].self, method: "GET", path: ["v1", "devices"], accessToken: session.accessToken())
        var verified = trusted
        var pending = devices
        while !pending.isEmpty {
            let before = pending.count
            var remaining: [WorkspaceCloudDevice] = []
            for device in pending {
                let publicKeys = WorkspaceDevicePublicKeys(signingKey: device.signingKey, encryptionKey: device.encryptionKey)
                if let known = verified[device.id] {
                    guard known == publicKeys else { throw WorkspaceSyncError.invalidSignature }
                    continue
                }
                guard let certificate = device.certificate, let signer = verified[certificate.signerID] else { remaining.append(device); continue }
                guard certificate.workspaceID == identity.workspaceID, certificate.epoch > 0 else { throw WorkspaceSyncError.identityMismatch }
                try WorkspaceDeviceKeys.verifyProof(certificate.signature, signingKey: signer.signingKey, domain: "BLOT-PAIR-APPROVE-1",
                    ids: [identity.workspaceID, certificate.pairingID, certificate.signerID, device.id],
                    values: [WorkspaceDeviceKeys.integer(certificate.epoch), device.signingKey, device.encryptionKey, certificate.wrappedKeys])
                verified[device.id] = publicKeys
            }
            guard remaining.count < before else { throw WorkspaceSyncError.invalidSignature }
            pending = remaining
        }
        try await remember(verified)
        return devices
    }

    private func account() async throws -> WorkspaceCloudTokens {
        guard let current = await session.current(), current.workspaceID == identity.workspaceID,
              current.ownerID == identity.ownerID else { throw WorkspaceSyncError.identityMismatch }
        return current
    }
    private func validate(_ invite: WorkspacePairingInvite, requireUnexpired: Bool = true) throws {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard invite.workspaceID == identity.workspaceID, invite.secret.utf8.count == 43,
              let expiry = formatter.date(from: invite.expiresAt) ?? ISO8601DateFormatter().date(from: invite.expiresAt), !requireUnexpired || expiry > Date() else {
            throw WorkspaceSyncError.identityMismatch
        }
        _ = try P256.Signing.PublicKey(x963Representation: invite.initiatorSigningKey)
        _ = try P256.KeyAgreement.PublicKey(x963Representation: invite.initiatorEncryptionKey)
    }
    private func remember(_ values: [UUID: WorkspaceDevicePublicKeys]) async throws {
        let previous = pendingTrust
        let worker = Task {
            if let previous { _ = try? await previous.value }
            try await self.persistTrust(values)
        }
        pendingTrust = worker
        try await worker.value
    }
    private func persistTrust(_ values: [UUID: WorkspaceDevicePublicKeys]) async throws {
        for (id, key) in values {
            if let old = trusted[id], old != key { throw WorkspaceSyncError.invalidSignature }
            _ = try P256.Signing.PublicKey(x963Representation: key.signingKey)
            _ = try P256.KeyAgreement.PublicKey(x963Representation: key.encryptionKey)
        }
        let next = trusted.merging(values, uniquingKeysWith: { old, _ in old })
        try await credentials.write(JSONEncoder().encode(next), name: trustName)
        trusted = next
    }
}

extension WorkspaceCloudDevices {
    public struct RevocationResult: Decodable, Equatable, Sendable {
        public let epoch: Int64
        public let stoppedTasks: [UUID]
    }
    private struct Revocation: Codable {
        let commandID: UUID
        let deviceID: UUID
        let newEpoch: Int64
        let grants: [String: Data]
        let signature: Data
    }
    private struct KeyGrant: Decodable, Sendable {
        let epoch: Int64
        let ciphertext: Data
        let signerID: UUID
        let signature: Data
    }
    private struct RotationManifest: Decodable {
        let workspaceID: UUID
        let signerID: UUID
        let revokedDeviceID: UUID
        let epoch: Int64
        let grants: [String: Data]
        let signature: Data
    }

    public func revoke(commandID: UUID, deviceID: UUID) async throws -> RevocationResult {
        guard deviceID != identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
        let pendingName = trustName + ":revocation:" + commandID.uuidString
        let request: Revocation
        if let saved = try await credentials.read(pendingName) {
            request = try JSONDecoder().decode(Revocation.self, from: saved)
            guard request.deviceID == deviceID, request.commandID == commandID else { throw WorkspaceStorageError.commandConflict }
        } else {
            let devices = try await refreshDeviceTrust()
            guard devices.contains(where: { $0.id == deviceID && !$0.revoked }) else { throw WorkspaceStorageError.missingRecord }
            let epoch = try await keys.prepareNextKeyEpoch()
            var grants: [String: Data] = [:]
            for device in devices where !device.revoked && device.id != deviceID {
                guard let known = trusted[device.id] else { throw WorkspaceSyncError.invalidSignature }
                grants[device.id.uuidString.lowercased()] = try await keys.wrapKeys(for: device.id, encryptionKey: known.encryptionKey, epoch: epoch, trustedDevices: trusted)
            }
            let signature = try await keys.signProof(domain: "BLOT-DEVICE-REVOKE-1", ids: [identity.workspaceID, identity.deviceID, deviceID],
                values: Self.rotationValues(epoch: epoch, grants: grants))
            request = Revocation(commandID: commandID, deviceID: deviceID, newEpoch: epoch, grants: grants, signature: signature)
            try await credentials.write(JSONEncoder().encode(request), name: pendingName)
        }
        let result = try await http.request(RevocationResult.self, method: "POST", path: ["v1", "devices", "revoke"],
            body: JSONEncoder().encode(request), accessToken: session.accessToken())
        guard result.epoch == request.newEpoch else { throw WorkspaceSyncError.unknownKeyEpoch }
        try await keys.activateKeyEpoch(result.epoch)
        return result
    }

    public func receiveKeyRotations() async throws -> Bool {
        let current = try await keys.currentEpoch()
        let grants = try await http.request([KeyGrant].self, method: "GET", path: ["v1", "devices", "keys"],
            query: ["afterEpoch": String(current)], accessToken: session.accessToken())
        guard grants.count <= 4096 else { throw WorkspaceSyncError.invalidChange }
        if !grants.isEmpty { _ = try await refreshDeviceTrust() }
        var epoch = current
        for grant in grants {
            guard epoch < Int64.max, grant.epoch == epoch + 1, grant.ciphertext.count <= 4 * 1024 * 1024 else { throw WorkspaceSyncError.unknownKeyEpoch }
            let manifest = try JSONDecoder().decode(RotationManifest.self, from: grant.ciphertext)
            guard manifest.workspaceID == identity.workspaceID, manifest.signerID == grant.signerID,
                  manifest.epoch == grant.epoch, manifest.signature == grant.signature,
                  manifest.revokedDeviceID != identity.deviceID, let wrapped = manifest.grants[identity.deviceID.uuidString.lowercased()],
                  let signer = trusted[manifest.signerID] else { throw WorkspaceSyncError.identityMismatch }
            try WorkspaceDeviceKeys.verifyProof(manifest.signature, signingKey: signer.signingKey, domain: "BLOT-DEVICE-REVOKE-1",
                ids: [identity.workspaceID, manifest.signerID, manifest.revokedDeviceID], values: Self.rotationValues(epoch: grant.epoch, grants: manifest.grants))
            let inherited = try await keys.acceptWrappedKeys(wrapped, signerID: manifest.signerID, epoch: manifest.epoch)
            try await remember(inherited)
            epoch = manifest.epoch
        }
        return epoch != current
    }

    private nonisolated static func rotationValues(epoch: Int64, grants: [String: Data]) throws -> [Data] {
        guard grants.count <= 16 else { throw WorkspaceSyncError.invalidChange }
        var values = [WorkspaceDeviceKeys.integer(epoch)]
        for id in grants.keys.sorted() {
            guard let uuid = UUID(uuidString: id), id == uuid.uuidString.lowercased(), let grant = grants[id], grant.count <= 131_072 else { throw WorkspaceSyncError.invalidChange }
            var raw = uuid.uuid
            values.append(withUnsafeBytes(of: &raw) { Data($0) }); values.append(grant)
        }
        return values
    }
}
