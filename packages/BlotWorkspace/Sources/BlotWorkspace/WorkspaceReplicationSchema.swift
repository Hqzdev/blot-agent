import CSQLite
import Foundation

enum WorkspaceReplicationSchema {
    static func install(_ database: SQLiteDatabase) throws {
        for definition in ["origin_device TEXT", "workspace_id TEXT", "owner_id TEXT", "vector TEXT", "changed_fields TEXT", "occurred_at TEXT"] {
            try database.execute("ALTER TABLE outbox ADD COLUMN " + definition)
        }
        try database.execute("CREATE TABLE replica_clock (origin TEXT PRIMARY KEY, sequence INTEGER NOT NULL)")
        try database.execute("CREATE TABLE replica_records (kind TEXT NOT NULL, id TEXT NOT NULL, vector TEXT NOT NULL, fields TEXT NOT NULL, origin TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY(kind, id))")
        try database.execute("CREATE TABLE replica_inbox (change_id TEXT PRIMARY KEY, origin TEXT NOT NULL, sequence INTEGER NOT NULL, digest TEXT NOT NULL, UNIQUE(origin, sequence))")
        try database.execute("CREATE TABLE replica_state (key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
        try database.execute("CREATE TABLE sealed_outbox (change_id TEXT PRIMARY KEY, epoch INTEGER NOT NULL, packet TEXT NOT NULL)")
        // Earlier local-only builds never sent ciphertext. Preserve their history and sequence numbering.
        guard let json = try database.query("SELECT value FROM local_settings WHERE key = 'identity'", row: { SQLiteDatabase.text($0, 0) }).first else { return }
        let identity = try WorkspaceCoding.decode(WorkspaceIdentity.self, from: Data(json.utf8))
        let entries = try database.query("SELECT sequence, change_id, kind, record_id, payload FROM outbox ORDER BY sequence") { row in
            (sqlite3_column_int64(row, 0), SQLiteDatabase.text(row, 1), SQLiteDatabase.text(row, 2), SQLiteDatabase.text(row, 3),
             sqlite3_column_type(row, 4) == SQLITE_NULL ? nil : SQLiteDatabase.text(row, 4))
        }
        var vector = WorkspaceVersionVector()
        for (sequence, changeID, kind, recordID, payload) in entries {
            vector.observe(identity.deviceID, sequence: sequence)
            let fields = try payload.map { Array(try JSONFields.object($0).keys.filter { $0 != "metadata" }).sorted() } ?? []
            let stamp = WorkspaceFieldStamp(vector: vector, origin: identity.deviceID, sequence: sequence)
            let clocks = Dictionary(uniqueKeysWithValues: fields.map { ($0, stamp) })
            let occurredAt = payload.flatMap { try? WorkspaceRecordCodec.decode(kind: kind, payload: $0).metadata.updatedAt } ?? Date(timeIntervalSince1970: 0)
            try database.execute("UPDATE outbox SET origin_device = ?, workspace_id = ?, owner_id = ?, vector = ?, changed_fields = ?, occurred_at = ? WHERE change_id = ?",
                [.text(identity.deviceID.uuidString), .text(identity.workspaceID.uuidString), .text(identity.ownerID.uuidString),
                 .text(String(decoding: WorkspaceCoding.encode(vector), as: UTF8.self)), .text(String(decoding: WorkspaceCoding.encode(fields), as: UTF8.self)),
                 .text(ISO8601DateFormatter().string(from: occurredAt)), .text(changeID)])
            try database.execute("INSERT INTO replica_records(kind, id, vector, fields, origin, sequence) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET vector = excluded.vector, fields = excluded.fields, origin = excluded.origin, sequence = excluded.sequence",
                [.text(kind), .text(recordID), .text(String(decoding: WorkspaceCoding.encode(vector), as: UTF8.self)),
                 .text(String(decoding: WorkspaceCoding.encode(clocks), as: UTF8.self)), .text(identity.deviceID.uuidString), .integer(sequence)])
        }
        if let last = entries.last?.0 {
            try database.execute("INSERT INTO replica_clock(origin, sequence) VALUES (?, ?)", [.text(identity.deviceID.uuidString.lowercased()), .integer(last)])
        }
    }
}
