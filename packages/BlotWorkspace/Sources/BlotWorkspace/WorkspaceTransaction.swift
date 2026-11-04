import BlotDomain
import CryptoKit
import Foundation

/// A command's scoped unit of work. It cannot be used after the repository closes its transaction.
public final class WorkspaceTransaction {
    private let store: WorkspaceRecordStore
    public let identity: WorkspaceIdentity
    private let commandID: UUID
    private var active = true

    init(store: WorkspaceRecordStore, identity: WorkspaceIdentity, commandID: UUID) {
        self.store = store
        self.identity = identity
        self.commandID = commandID
    }

    public func records<T: BlotWorkspaceRecord>(_ type: T.Type) throws -> [T] {
        try checkActive()
        return try store.records(type, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
    }

    public func record<T: BlotWorkspaceRecord>(_ type: T.Type, id: UUID) throws -> T? {
        try checkActive()
        guard let record = try store.record(type, id: id, workspaceID: identity.workspaceID),
              record.metadata.ownerId == identity.ownerID else { return nil }
        return record
    }

    public func require<T: BlotWorkspaceRecord>(_ type: T.Type, id: UUID, version: Int? = nil) throws -> T {
        guard let record = try record(type, id: id) else { throw WorkspaceStorageError.missingRecord }
        if let version, record.metadata.version != version { throw WorkspaceStorageError.versionConflict }
        return record
    }

    public func put<T: BlotWorkspaceRecord>(_ record: T, expectedVersion: Int) throws {
        try checkActive()
        guard record.metadata.ownerId == identity.ownerID, record.metadata.workspaceId == identity.workspaceID else {
            throw WorkspaceStorageError.permissionDenied
        }
        try store.write(WorkspaceRecordMutation(record, expectedVersion: expectedVersion), commandID: commandID)
    }

    func requireResolved(kind: String, id: UUID) throws {
        guard try !records(BlotV3.ConflictingRevision.self).contains(where: {
            !$0.resolved && $0.recordKind == kind && $0.recordId == id
        }) else { throw WorkspaceStorageError.unresolvedConflict }
    }

    public func delete<T: BlotWorkspaceRecord>(_ record: T) throws {
        try checkActive()
        guard record.metadata.ownerId == identity.ownerID, record.metadata.workspaceId == identity.workspaceID else {
            throw WorkspaceStorageError.permissionDenied
        }
        try store.write(WorkspaceRecordMutation(deleting: record), commandID: commandID)
    }

    public func metadata(id: UUID, now: Date, replacing previous: BlotV3.RecordMetadata? = nil) throws -> BlotV3.RecordMetadata {
        try checkActive()
        if let previous {
            guard previous.id == id, previous.ownerId == identity.ownerID, previous.workspaceId == identity.workspaceID else {
                throw WorkspaceStorageError.permissionDenied
            }
            guard previous.version < Int.max else { throw WorkspaceStorageError.invalidRecord }
        }
        return try .init(id: id, ownerId: identity.ownerID, workspaceId: identity.workspaceID,
            version: (previous?.version ?? 0) + 1, createdAt: previous?.createdAt ?? now, updatedAt: now)
    }

    func nextMessagePosition(in conversationID: UUID) throws -> Int {
        let messages = try records(BlotV3.Message.self).filter { $0.conversationId == conversationID }
        let latest = messages.enumerated().map { $0.element.position ?? $0.offset + 1 }.max() ?? 0
        guard latest < Int.max else { throw WorkspaceStorageError.invalidRecord }
        return latest + 1
    }

    func close() { active = false }
    private func checkActive() throws {
        guard active else { throw WorkspaceStorageError.transactionClosed }
    }
}

struct WorkspaceCommand<Payload: Encodable>: Encodable {
    let type: String
    let workspaceID: UUID
    let payload: Payload

    func data() throws -> Data { try WorkspaceCoding.encode(self) }
}

enum WorkspaceLogicalID {
    static func make(kind: String, workspaceID: UUID, parts: [String]) -> UUID {
        let input = ([kind, workspaceID.uuidString.lowercased()] + parts).map { "\($0.utf8.count):\($0)" }.joined()
        var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
