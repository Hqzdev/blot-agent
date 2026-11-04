import BlotDomain
import Foundation

enum WorkspaceCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public struct WorkspaceRecordMutation: Sendable {
    let kind: String
    let id: UUID
    let workspaceID: UUID
    let version: Int
    let expectedVersion: Int
    let payload: String?
    let searchableContent: String?

    public init<T: BlotWorkspaceRecord>(_ record: T, expectedVersion: Int) throws {
        guard let workspaceID = record.metadata.workspaceId, expectedVersion >= 0, expectedVersion < Int.max,
              record.metadata.version == expectedVersion + 1 else { throw WorkspaceStorageError.invalidRecord }
        self.kind = T.recordKind
        self.id = record.metadata.id
        self.workspaceID = workspaceID
        self.version = record.metadata.version
        self.expectedVersion = expectedVersion
        let encoded = try WorkspaceCoding.encode(record)
        guard encoded.count <= 192 * 1024 else { throw WorkspaceStorageError.invalidRecord }
        self.payload = String(decoding: encoded, as: UTF8.self)
        self.searchableContent = (record as? BlotV3.Message)?.content
    }

    public init<T: BlotWorkspaceRecord>(deleting record: T) throws {
        guard let workspaceID = record.metadata.workspaceId, record.metadata.version < Int.max else { throw WorkspaceStorageError.invalidRecord }
        self.kind = T.recordKind
        self.id = record.metadata.id
        self.workspaceID = workspaceID
        self.version = record.metadata.version + 1
        self.expectedVersion = record.metadata.version
        self.payload = nil
        self.searchableContent = nil
    }
}

/// Local pending change. A relay adapter must encrypt this payload before transport.
public struct PendingWorkspaceChange: Equatable, Sendable {
    public let sequence: Int64
    public let changeID: UUID
    public let commandID: UUID
    public let kind: String
    public let recordID: UUID
    public let version: Int
    public let payload: String?
    public let deleted: Bool
}

public struct WorkspaceIdentity: Codable, Equatable, Sendable {
    public let ownerID: UUID
    public let workspaceID: UUID
    public let deviceID: UUID

    public init(ownerID: UUID, workspaceID: UUID, deviceID: UUID) {
        self.ownerID = ownerID
        self.workspaceID = workspaceID
        self.deviceID = deviceID
    }
}
