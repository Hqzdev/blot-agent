import BlotDomain
import CSQLite
import Foundation

/// Synchronous record access, shared by read projections and command transactions.
final class WorkspaceRecordStore {
    private let database: SQLiteDatabase
    private let replicas: WorkspaceReplicaStore
    private let index: WorkspaceRecordIndex
    private final class DecodedRecord {
        let payload: String
        let value: Any
        init(payload: String, value: Any) { self.payload = payload; self.value = value }
    }
    // Compare the actual payload, not only its version: replica reconciliation and rollback
    // can replace content without advancing the visible version. Never cache authorization.
    private let decoded: NSCache<NSString, DecodedRecord> = {
        let cache = NSCache<NSString, DecodedRecord>()
        cache.countLimit = 2048; cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    init(database: SQLiteDatabase) { self.database = database; self.replicas = WorkspaceReplicaStore(database: database); self.index = WorkspaceRecordIndex(database: database) }

    func executionAdmitted(_ task: BlotV3.Task, identity: WorkspaceIdentity) throws -> Bool {
        guard task.execution.executorDeviceId == identity.deviceID else { return false }
        if try database.query("SELECT value FROM local_settings WHERE key = ?", [.text("task-terminal:" + task.metadata.id.uuidString)], row: { SQLiteDatabase.text($0, 0) }).first != nil { return false }
        let local = try database.query("SELECT version,payload FROM outbox WHERE kind = 'Task' AND record_id = ? AND origin_device = ? AND deleted = 0",
            [.text(task.metadata.id.uuidString), .text(identity.deviceID.uuidString)]) { row in
                (Int(sqlite3_column_int64(row, 0)), SQLiteDatabase.text(row, 1))
            }
        var createdHere = false
        for (version, payload) in local {
            guard let old = try? WorkspaceCoding.decode(BlotV3.Task.self, from: Data(payload.utf8)) else { continue }
            if WorkspaceTaskService.terminal(old.state) { return false }
            if version == 1 {
                createdHere = old.execution == task.execution && old.metadata.ownerId == task.metadata.ownerId
                    && old.metadata.workspaceId == task.metadata.workspaceId && old.conversationId == task.conversationId
                    && old.projectId == task.projectId && old.goal == task.goal && old.configurationId == task.configurationId
                    && old.parentTaskId == task.parentTaskId && old.skillRevisionId == task.skillRevisionId
                    && old.budgetTokenLimit == task.budgetTokenLimit && old.executionMode == task.executionMode
                    && old.authorizationJSON == task.authorizationJSON
            }
        }
        if task.executionMode == .delegated { return task.execution.originDeviceId != identity.deviceID && task.authorizationJSON != nil }
        return task.executionMode == .local_owned && task.execution.originDeviceId == identity.deviceID && createdHere
    }

    func records<T: BlotWorkspaceRecord>(_ type: T.Type, workspaceID: UUID) throws -> [T] {
        try database.query("SELECT id,payload FROM records WHERE kind = ? AND workspace_id = ? AND deleted = 0 ORDER BY rowid",
            [.text(T.recordKind), .text(workspaceID.uuidString)]) {
                try decode(type, id: SQLiteDatabase.text($0, 0), workspaceID: workspaceID, payload: SQLiteDatabase.text($0, 1))
            }
    }

    func record<T: BlotWorkspaceRecord>(_ type: T.Type, id: UUID, workspaceID: UUID) throws -> T? {
        try database.query("SELECT payload FROM records WHERE kind = ? AND id = ? AND workspace_id = ? AND deleted = 0",
            [.text(T.recordKind), .text(id.uuidString), .text(workspaceID.uuidString)]) {
                try decode(type, id: id.uuidString, workspaceID: workspaceID, payload: SQLiteDatabase.text($0, 0))
            }.first
    }

    private func decode<T: BlotWorkspaceRecord>(_ type: T.Type, id: String, workspaceID: UUID, payload: String) throws -> T {
        let key = (workspaceID.uuidString + ":" + T.recordKind + ":" + id) as NSString
        if let cached = decoded.object(forKey: key), cached.payload == payload, let value = cached.value as? T { return value }
        let value = try WorkspaceCoding.decode(type, from: Data(payload.utf8))
        decoded.setObject(DecodedRecord(payload: payload, value: value), forKey: key, cost: payload.utf8.count * 3 + 256)
        return value
    }

    func write(_ mutation: WorkspaceRecordMutation, commandID: UUID) throws {
        let existing = try database.query("SELECT version, deleted, workspace_id, payload FROM records WHERE kind = ? AND id = ?",
            [.text(mutation.kind), .text(mutation.id.uuidString)]) {
                (Int(sqlite3_column_int64($0, 0)), sqlite3_column_int($0, 1) != 0, SQLiteDatabase.text($0, 2), sqlite3_column_type($0, 3) == SQLITE_NULL ? nil : SQLiteDatabase.text($0, 3))
            }.first
        if existing?.1 == true { throw WorkspaceStorageError.deletedRecord }
        guard (existing?.0 ?? 0) == mutation.expectedVersion,
              existing.map({ $0.2 == mutation.workspaceID.uuidString }) ?? true else { throw WorkspaceStorageError.versionConflict }
        let payload: SQLiteDatabase.Value = mutation.payload.map { .text($0) } ?? .null
        let deleted: SQLiteDatabase.Value = .integer(mutation.payload == nil ? 1 : 0)
        try database.execute("""
            INSERT INTO records(kind, id, workspace_id, version, payload, deleted) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(kind, id) DO UPDATE SET version = excluded.version, payload = excluded.payload, deleted = excluded.deleted
            """, [.text(mutation.kind), .text(mutation.id.uuidString), .text(mutation.workspaceID.uuidString), .integer(Int64(mutation.version)), payload, deleted])
        let pending = try coalescingChange(for: mutation)
        let changeID = pending ?? UUID()
        if pending != nil {
            try database.execute("UPDATE outbox SET version = ?, payload = ?, deleted = ? WHERE change_id = ?",
                [.integer(Int64(mutation.version)), payload, deleted, .text(changeID.uuidString)])
        } else {
            try database.execute("INSERT INTO outbox(change_id, command_id, kind, record_id, version, payload, deleted) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [.text(changeID.uuidString), .text(commandID.uuidString), .text(mutation.kind), .text(mutation.id.uuidString), .integer(Int64(mutation.version)), payload, deleted])
        }
        guard let sequence = try database.query("SELECT sequence FROM outbox WHERE change_id = ?", [.text(changeID.uuidString)], row: { sqlite3_column_int64($0, 0) }).first else { throw WorkspaceStorageError.invalidRecord }
        try replicas.recordLocal(mutation, changeID: changeID, sequence: sequence, previousPayload: existing?.3, coalescing: pending != nil)
        try index.update(kind: mutation.kind, id: mutation.id, workspaceID: mutation.workspaceID, content: mutation.searchableContent)
    }

    private func coalescingChange(for mutation: WorkspaceRecordMutation) throws -> UUID? {
        guard mutation.kind == "Message", let payload = mutation.payload,
              try WorkspaceCoding.decode(BlotV3.Message.self, from: Data(payload.utf8)).role == .assistant else { return nil }
        return try database.query("""
            SELECT change_id FROM outbox
            WHERE kind = ? AND record_id = ? AND acknowledged = 0 AND in_flight = 0
              AND sequence = (SELECT seq FROM sqlite_sequence WHERE name = 'outbox')
              AND NOT EXISTS (SELECT 1 FROM sealed_outbox s WHERE s.change_id = outbox.change_id)
            """, [.text(mutation.kind), .text(mutation.id.uuidString)]) { row in
                guard let id = UUID(uuidString: SQLiteDatabase.text(row, 0)) else { throw WorkspaceStorageError.invalidRecord }
                return id
            }.first
    }

}
