import Foundation

public enum WorkspaceSyncError: Error, Equatable, Sendable {
    case invalidChange, unsupportedRecord, identityMismatch, sequenceGap, causalGap, replayConflict
    case invalidSignature, unknownKeyEpoch, replayUnavailable, immutableRecordConflict, invalidSnapshot
}

public struct WorkspaceVersionVector: Codable, Equatable, Sendable {
    private(set) var values: [String: Int64]

    public init() { values = [:] }
    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer().decode([String: Int64].self)
        guard values.count <= 4096, values.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.key == $0.key.lowercased() && $0.value >= 0 }) else {
            throw WorkspaceSyncError.invalidChange
        }
        self.values = values
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(values)
    }
    public func sequence(for deviceID: UUID) -> Int64 { values[deviceID.uuidString.lowercased()] ?? 0 }
    mutating func observe(_ deviceID: UUID, sequence: Int64) {
        values[deviceID.uuidString.lowercased()] = max(self.sequence(for: deviceID), sequence)
    }
    func merged(with other: Self) -> Self {
        var result = self
        for (origin, sequence) in other.values { result.values[origin] = max(result.values[origin] ?? 0, sequence) }
        return result
    }
    func dominates(_ other: Self) -> Bool { other.values.allSatisfy { (values[$0.key] ?? 0) >= $0.value } }
}

public struct WorkspaceSyncChange: Codable, Equatable, Sendable {
    public let changeID: UUID
    public let workspaceID: UUID
    public let ownerID: UUID
    public let originDeviceID: UUID
    public let sequence: Int64
    public let kind: String
    public let recordID: UUID
    public let version: Int
    public let payload: String?
    public let deleted: Bool
    public let vector: WorkspaceVersionVector
    public let changedFields: [String]
    public let occurredAt: Date
}

struct WorkspaceFieldStamp: Codable, Equatable, Sendable {
    let vector: WorkspaceVersionVector
    let origin: UUID
    let sequence: Int64

    func wins(over other: Self) -> Bool {
        if vector.dominates(other.vector) { return true }
        if other.vector.dominates(vector) { return false }
        return origin.uuidString == other.origin.uuidString ? sequence > other.sequence : origin.uuidString > other.origin.uuidString
    }
}

public struct WorkspaceReplicaRecord: Codable, Equatable, Sendable {
    let kind: String
    let recordID: UUID
    let version: Int
    let payload: String?
    let deleted: Bool
    let vector: WorkspaceVersionVector
    let fields: [String: WorkspaceFieldStamp]
    let origin: UUID
    let sequence: Int64
}

public struct WorkspaceReplicaSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let workspaceID: UUID
    public let ownerID: UUID
    public let watermark: WorkspaceVersionVector
    public let relayCursor: Int64
    public let records: [WorkspaceReplicaRecord]
}

enum JSONFields {
    static func object(_ payload: String) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { throw WorkspaceSyncError.invalidChange }
        return value
    }
    static func string(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
    }
    static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        guard let left = try? string(lhs), let right = try? string(rhs) else { return false }
        return left == right
    }
}
