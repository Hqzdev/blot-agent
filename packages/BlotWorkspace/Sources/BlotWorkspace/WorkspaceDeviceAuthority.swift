import BlotDomain
import CryptoKit
import Foundation

public struct WorkspacePairedDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let kind: BlotV3.DeviceKind
    public let signingKey: Data
    public let pairingID: UUID
    public var revoked: Bool
}
public struct WorkspacePairingClaim: Sendable {
    public let token: String
    public let code: String
    public let name: String
}

/// Trust is pinned in this installation's credential store, never inferred from cloud device records.
public actor WorkspaceDeviceAuthority {
    private struct Payload: Codable, Sendable {
        let kind: String; let ownerID: UUID; let workspaceID: UUID; let id: UUID
        let originID: UUID; let targetID: UUID?; let name: String; let key: Data; let expires: Date; let proof: Data
    }
    private struct Packet: Codable, Sendable { let payload: Payload; let signature: Data }
    private struct State: Codable { var peers: [UUID: WorkspacePairedDevice] = [:]; var invites: [UUID: String] = [:]; var claims: [UUID: String] = [:] }
    public let identity: WorkspaceIdentity
    private let keys: WorkspaceDeviceKeys
    private let persistence: WorkspaceCredentialPersistence
    private var state: State
    private var generation = 0
    private var pending: _Concurrency.Task<Void, Error>?
    private init(identity: WorkspaceIdentity, keys: WorkspaceDeviceKeys, credentials: any WorkspaceCredentialStore, state: State) {
        self.identity = identity; self.keys = keys; self.state = state
        persistence = .init(store: credentials, name: Self.credentialName(identity))
    }
    public static func credentialName(_ identity: WorkspaceIdentity) -> String { "device-authority:" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    public static func open(identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore) async throws -> WorkspaceDeviceAuthority {
        let keys = try await WorkspaceDeviceKeys.open(identity: identity, credentials: credentials)
        let data = try await credentials.read(credentialName(identity))
        let state = try data.map { try WorkspaceCoding.decode(State.self, from: $0) } ?? State()
        guard state.peers.count <= 100, state.invites.count <= 20, state.claims.count <= 20 else { throw WorkspaceStorageError.invalidRecord }
        return .init(identity: identity, keys: keys, credentials: credentials, state: state)
    }
    public func devices() async throws -> [WorkspacePairedDevice] { try await settle(); return state.peers.values.sorted { $0.name < $1.name } }
    public func invite(name: String, now: Date = Date()) async throws -> String {
        try await settle(); let expected = generation
        let token = try await packet(kind: "invite", id: UUID(), target: nil, name: name, proof: Data(), expires: now.addingTimeInterval(600))
        let value = try decode(token, now: now)
        var next = state; next.invites = [:]; next.invites[value.payload.id] = token
        try await commit(next, expected: expected); return token
    }
    public func claim(_ token: String, name: String, now: Date = Date()) async throws -> WorkspacePairingClaim {
        try await settle(); let expected = generation
        let invite = try decode(token, now: now)
        guard invite.payload.kind == "invite", invite.payload.originID != identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
        let claim = try await packet(kind: "claim", id: invite.payload.id, target: invite.payload.originID, name: name, proof: Data(token.utf8), expires: invite.payload.expires)
        let value = try decode(claim, now: now)
        var next = state; next.claims = [:]; next.claims[value.payload.id] = claim
        try await commit(next, expected: expected)
        return .init(token: claim, code: try code(invite: invite, claim: value), name: invite.payload.name)
    }
    public func inspect(_ token: String, now: Date = Date()) async throws -> WorkspacePairingClaim {
        try await settle()
        let claim = try decode(token, now: now)
        guard claim.payload.kind == "claim", claim.payload.targetID == identity.deviceID,
              let inviteToken = state.invites[claim.payload.id], claim.payload.proof == Data(inviteToken.utf8) else { throw WorkspaceStorageError.permissionDenied }
        let invite = try decode(inviteToken, now: now)
        return .init(token: token, code: try code(invite: invite, claim: claim), name: claim.payload.name)
    }
    public func approve(_ token: String, confirmedCode: String, now: Date = Date()) async throws -> String {
        let inspection = try await inspect(token, now: now); let expected = generation
        guard inspection.code == confirmedCode else { throw WorkspaceStorageError.permissionDenied }
        let claim = try decode(token, now: now)
        let approval = try await packet(kind: "approval", id: claim.payload.id, target: claim.payload.originID, name: "Mac", proof: Data(token.utf8), expires: claim.payload.expires)
        var next = state
        next.peers[claim.payload.originID] = .init(id: claim.payload.originID, name: claim.payload.name, kind: .phone, signingKey: claim.payload.key, pairingID: claim.payload.id, revoked: false)
        next.invites[claim.payload.id] = nil
        try await commit(next, expected: expected); return approval
    }
    public func finish(_ token: String, now: Date = Date()) async throws {
        try await settle(); let expected = generation
        let approval = try decode(token, now: now)
        guard approval.payload.kind == "approval", approval.payload.targetID == identity.deviceID,
              let claimToken = state.claims[approval.payload.id], approval.payload.proof == Data(claimToken.utf8) else { throw WorkspaceStorageError.permissionDenied }
        let claim = try decode(claimToken, now: now)
        guard let inviteToken = String(data: claim.payload.proof, encoding: .utf8) else { throw WorkspaceStorageError.invalidParameters }
        let invite = try decode(inviteToken, now: now)
        guard approval.payload.key == invite.payload.key, approval.payload.originID == invite.payload.originID else { throw WorkspaceSyncError.invalidSignature }
        var next = state
        next.peers[approval.payload.originID] = .init(id: approval.payload.originID, name: invite.payload.name, kind: .desktop, signingKey: approval.payload.key, pairingID: approval.payload.id, revoked: false)
        next.claims[approval.payload.id] = nil
        try await commit(next, expected: expected)
    }
    public func revoke(_ id: UUID) async throws {
        try await settle(); let expected = generation
        guard var peer = state.peers[id] else { throw WorkspaceStorageError.missingRecord }
        peer.revoked = true; var next = state; next.peers[id] = peer
        try await commit(next, expected: expected)
    }
    public func peer(_ id: UUID) async throws -> WorkspacePairedDevice {
        try await settle()
        guard let peer = state.peers[id], !peer.revoked else { throw WorkspaceStorageError.permissionDenied }; return peer
    }
    func signDelegation(_ data: Data, version: Int = 1) async throws -> Data {
        guard version == 1 || version == 2 else { throw WorkspaceStorageError.permissionDenied }
        return try await keys.signProof(domain: "BLOT-TASK-DELEGATION-" + String(version), ids: [identity.ownerID, identity.workspaceID], values: [data])
    }
    private func packet(kind: String, id: UUID, target: UUID?, name: String, proof: Data, expires: Date) async throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw WorkspaceStorageError.invalidParameters }
        let payload = Payload(kind: kind, ownerID: identity.ownerID, workspaceID: identity.workspaceID, id: id,
            originID: identity.deviceID, targetID: target, name: name, key: try await keys.publicKeys().signingKey,
            expires: Date(timeIntervalSince1970: floor(expires.timeIntervalSince1970)), proof: proof)
        let signature = try await keys.signProof(domain: "BLOT-DEVICE-PAIR-1", ids: [identity.ownerID, identity.workspaceID], values: [WorkspaceCoding.encode(payload)])
        return "blot-pair:" + (try WorkspaceCoding.encode(Packet(payload: payload, signature: signature))).base64EncodedString()
    }
    private func decode(_ token: String, now: Date) throws -> Packet {
        guard token.utf8.count <= 32_768, token.hasPrefix("blot-pair:"), let data = Data(base64Encoded: String(token.dropFirst(10))) else { throw WorkspaceStorageError.invalidParameters }
        let packet = try WorkspaceCoding.decode(Packet.self, from: data), p = packet.payload
        guard p.ownerID == identity.ownerID, p.workspaceID == identity.workspaceID, p.expires > now, p.expires <= now.addingTimeInterval(900) else { throw WorkspaceStorageError.permissionDenied }
        try WorkspaceDeviceKeys.verifyProof(packet.signature, signingKey: p.key, domain: "BLOT-DEVICE-PAIR-1", ids: [identity.ownerID, identity.workspaceID], values: [WorkspaceCoding.encode(p)])
        return packet
    }
    private func code(invite: Packet, claim: Packet) throws -> String {
        let data = Data(SHA256.hash(data: (try WorkspaceCoding.encode(invite.payload)) + (try WorkspaceCoding.encode(claim.payload))))
        let number = data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", number % 1_000_000)
    }
    private func settle() async throws { if let pending { try await pending.value } }
    private func commit(_ next: State, expected: Int) async throws {
        guard next.peers.count <= 100, generation == expected else { throw WorkspaceStorageError.versionConflict }
        let old = state; let bytes = try WorkspaceCoding.encode(next)
        let writer = _Concurrency.Task { try await persistence.replace(with: bytes) }
        pending = writer; generation += 1; state = next
        do { try await writer.value; if generation == expected + 1 { pending = nil } }
        catch { if generation == expected + 1 { state = old; pending = nil }; throw error }
    }
}
