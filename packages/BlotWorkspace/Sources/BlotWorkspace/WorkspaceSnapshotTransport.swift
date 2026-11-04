import Foundation

public struct WorkspaceSnapshotRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let requesterDeviceID: UUID
    public let minimumCursor: Int64
    public let expiresAt: String
}

public struct WorkspaceSnapshotOffer: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let snapshotID: UUID
    public let donorDeviceID: UUID
    public let keyEpoch: Int64
    public let relayCursor: Int64
    public let byteCount: Int
    public let chunkCount: Int
    public let digest: String
    public let packetSignature: Data
    public let signature: Data

    func proofIDs(workspaceID: UUID) -> [UUID] { [workspaceID, requestID, snapshotID, donorDeviceID] }
    var proofValues: [Data] {
        [keyEpoch, relayCursor, Int64(byteCount), Int64(chunkCount)].map(WorkspaceDeviceKeys.integer)
            + [Data(digest.utf8), packetSignature]
    }
    func signed(_ signature: Data) -> Self {
        Self(requestID: requestID, snapshotID: snapshotID, donorDeviceID: donorDeviceID, keyEpoch: keyEpoch,
             relayCursor: relayCursor, byteCount: byteCount, chunkCount: chunkCount, digest: digest,
             packetSignature: packetSignature, signature: signature)
    }
    func packet(workspaceID: UUID, ciphertext: Data) -> WorkspaceEncryptedPacket {
        .init(kind: .snapshot, workspaceID: workspaceID, originDeviceID: donorDeviceID, changeID: snapshotID,
              sequence: 0, keyEpoch: keyEpoch, ciphertext: ciphertext, signature: packetSignature)
    }
}

public struct WorkspaceSnapshotStatus: Codable, Equatable, Sendable {
    public let request: WorkspaceSnapshotRequest
    public let offer: WorkspaceSnapshotOffer?
}

public protocol WorkspaceSnapshotTransport: Sendable {
    func request(id: UUID, minimumCursor: Int64) async throws -> WorkspaceSnapshotStatus
    func status(id: UUID) async throws -> WorkspaceSnapshotStatus
    func pending() async throws -> [WorkspaceSnapshotRequest]
    func publish(_ offer: WorkspaceSnapshotOffer) async throws
}

public struct WorkspaceCloudSnapshotTransport: WorkspaceSnapshotTransport {
    private let http: WorkspaceCloudHTTP
    private let authorization: any WorkspaceCloudAuthorization
    public init(http: WorkspaceCloudHTTP, authorization: any WorkspaceCloudAuthorization) { self.http = http; self.authorization = authorization }
    public func request(id: UUID, minimumCursor: Int64) async throws -> WorkspaceSnapshotStatus {
        struct Input: Encodable { let requestID: UUID; let minimumCursor: Int64 }
        return try await http.request(WorkspaceSnapshotStatus.self, method: "POST", path: ["v1", "relay", "snapshots"],
            body: JSONEncoder().encode(Input(requestID: id, minimumCursor: minimumCursor)), accessToken: authorization.accessToken())
    }
    public func status(id: UUID) async throws -> WorkspaceSnapshotStatus {
        try await http.request(WorkspaceSnapshotStatus.self, method: "GET", path: ["v1", "relay", "snapshots", id.uuidString], accessToken: authorization.accessToken())
    }
    public func pending() async throws -> [WorkspaceSnapshotRequest] {
        try await http.request([WorkspaceSnapshotRequest].self, method: "GET", path: ["v1", "relay", "snapshots"], accessToken: authorization.accessToken())
    }
    public func publish(_ offer: WorkspaceSnapshotOffer) async throws {
        try await http.empty(method: "POST", path: ["v1", "relay", "snapshots", "offers"], body: JSONEncoder().encode(offer), accessToken: authorization.accessToken())
    }
}
