import BlotDomain
import CryptoKit
import CSQLite
import Foundation

/// Replica state is mutated only inside a repository transaction, together with the delivery cursor.
final class WorkspaceReplicaStore {
    private let database: SQLiteDatabase
    private let index: WorkspaceRecordIndex
    private static let cloudKinds: Set<String> = ["Account", "Device", "TrustedPair", "Workspace", "ExecutionLease", "SyncCursor", "ReplicationCheckpoint", "RecordChange"]

    init(database: SQLiteDatabase) { self.database = database; self.index = WorkspaceRecordIndex(database: database) }

    func clock() throws -> WorkspaceVersionVector {
        var result = WorkspaceVersionVector()
        for (id, sequence) in try database.query("SELECT origin, sequence FROM replica_clock", row: { (SQLiteDatabase.text($0, 0), sqlite3_column_int64($0, 1)) }) {
            guard let origin = UUID(uuidString: id) else { throw WorkspaceSyncError.invalidChange }
            result.observe(origin, sequence: sequence)
        }
        return result
    }

    func recordLocal(_ mutation: WorkspaceRecordMutation, changeID: UUID, sequence: Int64, previousPayload: String?, coalescing: Bool = false) throws {
        guard let json = try database.query("SELECT value FROM local_settings WHERE key = 'identity'", row: { SQLiteDatabase.text($0, 0) }).first else {
            throw WorkspaceSyncError.identityMismatch
        }
        let identity = try WorkspaceCoding.decode(WorkspaceIdentity.self, from: Data(json.utf8))
        guard identity.workspaceID == mutation.workspaceID else { throw WorkspaceSyncError.identityMismatch }
        var vector = try clock()
        vector.observe(identity.deviceID, sequence: sequence)
        let incoming = try mutation.payload.map(JSONFields.object) ?? [:]
        let previous = try previousPayload.map(JSONFields.object) ?? [:]
        var changed = incoming.keys.filter { $0 != "metadata" && !JSONFields.equal(incoming[$0], previous[$0]) }.sorted()
        if coalescing {
            let prior = try database.query("SELECT COALESCE(changed_fields, '[]') FROM outbox WHERE change_id = ?", [.text(changeID.uuidString)], row: { SQLiteDatabase.text($0, 0) }).first ?? "[]"
            changed = Array(Set(changed).union(try WorkspaceCoding.decode([String].self, from: Data(prior.utf8)))).sorted()
        }
        var fields = try state(kind: mutation.kind, id: mutation.id)?.fields ?? [:]
        let stamp = WorkspaceFieldStamp(vector: vector, origin: identity.deviceID, sequence: sequence)
        for key in changed { fields[key] = stamp }
        let occurredAt = mutation.payload.flatMap { try? WorkspaceRecordCodec.decode(kind: mutation.kind, payload: $0).metadata.updatedAt } ?? Date()
        try database.execute("UPDATE outbox SET origin_device = ?, workspace_id = ?, owner_id = ?, vector = ?, changed_fields = ?, occurred_at = ? WHERE change_id = ?",
            [.text(identity.deviceID.uuidString), .text(identity.workspaceID.uuidString), .text(identity.ownerID.uuidString),
             .text(try jsonString(vector)), .text(try jsonString(changed)), .text(ISO8601DateFormatter().string(from: occurredAt)), .text(changeID.uuidString)])
        try saveState(.init(kind: mutation.kind, recordID: mutation.id, version: mutation.version, payload: mutation.payload,
            deleted: mutation.payload == nil, vector: vector, fields: fields, origin: identity.deviceID, sequence: sequence))
        try advanceClock(identity.deviceID, to: sequence)
    }

    func apply(_ change: WorkspaceSyncChange, identity: WorkspaceIdentity) throws {
        guard change.workspaceID == identity.workspaceID, change.ownerID == identity.ownerID, change.sequence > 0,
              change.version > 0, change.vector.sequence(for: change.originDeviceID) == change.sequence,
              change.deleted == (change.payload == nil), !Self.cloudKinds.contains(change.kind), WorkspaceRecordCodec.supportedKinds.contains(change.kind),
              Set(change.changedFields).count == change.changedFields.count, !change.changedFields.contains("metadata") else {
            throw WorkspaceSyncError.invalidChange
        }
        let digest = SHA256.hash(data: try WorkspaceCoding.encode(change)).map { String(format: "%02x", $0) }.joined()
        if let known = try database.query("SELECT digest FROM replica_inbox WHERE change_id = ? OR (origin = ? AND sequence = ?)",
            [.text(change.changeID.uuidString), .text(change.originDeviceID.uuidString), .integer(change.sequence)], row: { SQLiteDatabase.text($0, 0) }).first {
            guard known == digest else { throw WorkspaceSyncError.replayConflict }
            return
        }
        let clock = try clock()
        if change.sequence > clock.sequence(for: change.originDeviceID) {
            guard clock.sequence(for: change.originDeviceID) < Int64.max,
                  change.sequence == clock.sequence(for: change.originDeviceID) + 1 else { throw WorkspaceSyncError.sequenceGap }
            for (origin, sequence) in change.vector.values where origin != change.originDeviceID.uuidString.lowercased() {
                guard (clock.values[origin] ?? 0) >= sequence else { throw WorkspaceSyncError.causalGap }
            }
            let fields = Dictionary(uniqueKeysWithValues: change.changedFields.map {
                ($0, WorkspaceFieldStamp(vector: change.vector, origin: change.originDeviceID, sequence: change.sequence))
            })
            try merge(.init(kind: change.kind, recordID: change.recordID, version: change.version, payload: change.payload,
                deleted: change.deleted, vector: change.vector, fields: fields, origin: change.originDeviceID, sequence: change.sequence), identity: identity)
            try advanceClock(change.originDeviceID, to: change.sequence)
        }
        try database.execute("INSERT INTO replica_inbox(change_id, origin, sequence, digest) VALUES (?, ?, ?, ?)",
            [.text(change.changeID.uuidString), .text(change.originDeviceID.uuidString), .integer(change.sequence), .text(digest)])
    }

    func snapshot(identity: WorkspaceIdentity, cursor: Int64) throws -> WorkspaceReplicaSnapshot {
        let records = try database.query("SELECT kind, id FROM records WHERE workspace_id = ?", [.text(identity.workspaceID.uuidString)]) { row in
            (SQLiteDatabase.text(row, 0), SQLiteDatabase.text(row, 1))
        }.compactMap { kind, id -> WorkspaceReplicaRecord? in
            guard !Self.cloudKinds.contains(kind), let id = UUID(uuidString: id) else { return nil }
            return try state(kind: kind, id: id)
        }
        return WorkspaceReplicaSnapshot(id: UUID(), workspaceID: identity.workspaceID, ownerID: identity.ownerID,
            watermark: try clock(), relayCursor: cursor, records: records)
    }

    func install(_ snapshot: WorkspaceReplicaSnapshot, identity: WorkspaceIdentity) throws {
        guard snapshot.workspaceID == identity.workspaceID, snapshot.ownerID == identity.ownerID, snapshot.relayCursor >= 0,
              Set(snapshot.records.map { $0.kind + ":" + $0.recordID.uuidString }).count == snapshot.records.count else { throw WorkspaceSyncError.invalidSnapshot }
        for record in snapshot.records {
            guard snapshot.watermark.dominates(record.vector) else { throw WorkspaceSyncError.invalidSnapshot }
            try merge(record, identity: identity)
        }
        for (origin, sequence) in snapshot.watermark.values {
            guard let id = UUID(uuidString: origin) else { throw WorkspaceSyncError.invalidSnapshot }
            try advanceClock(id, to: sequence)
        }
        // Keep the local nonce/sequence monotonic if this device's own history is part of the snapshot.
        let ownSequence = snapshot.watermark.sequence(for: identity.deviceID)
        let stored = try database.query("SELECT seq FROM sqlite_sequence WHERE name = 'outbox'", row: { sqlite3_column_int64($0, 0) }).first
        if let stored, stored < ownSequence { try database.execute("UPDATE sqlite_sequence SET seq = ? WHERE name = 'outbox'", [.integer(ownSequence)]) }
        else if stored == nil && ownSequence > 0 { try database.execute("INSERT INTO sqlite_sequence(name, seq) VALUES ('outbox', ?)", [.integer(ownSequence)]) }
    }

    private func merge(_ incoming: WorkspaceReplicaRecord, identity: WorkspaceIdentity) throws {
        guard !Self.cloudKinds.contains(incoming.kind), WorkspaceRecordCodec.supportedKinds.contains(incoming.kind), incoming.version > 0, incoming.sequence > 0,
              incoming.vector.sequence(for: incoming.origin) >= incoming.sequence,
              incoming.deleted == (incoming.payload == nil),
              incoming.fields.values.allSatisfy({ $0.sequence > 0 && $0.vector.sequence(for: $0.origin) == $0.sequence && incoming.vector.dominates($0.vector) })
              else { throw WorkspaceSyncError.invalidChange }
        let decoded = try incoming.payload.map { try WorkspaceRecordCodec.decode(kind: incoming.kind, payload: $0) }
        if let decoded {
            guard decoded.metadata.id == incoming.recordID, decoded.metadata.version == incoming.version,
                  decoded.metadata.ownerId == identity.ownerID, decoded.metadata.workspaceId == identity.workspaceID else { throw WorkspaceSyncError.identityMismatch }
            let keys = Set(try JSONFields.object(decoded.payload).keys).subtracting(["metadata"])
            guard Set(incoming.fields.keys).isSubset(of: keys) else { throw WorkspaceSyncError.invalidChange }
            if incoming.kind == "Message" {
                let message = try WorkspaceCoding.decode(BlotV3.Message.self, from: Data(decoded.payload.utf8))
                if message.role == .assistant, let executor = message.executorDeviceId, executor != incoming.origin { throw WorkspaceSyncError.identityMismatch }
            }
        }
        guard let current = try state(kind: incoming.kind, id: incoming.recordID) else {
            try persist(incoming, identity: identity)
            return
        }
        let vector = current.vector.merged(with: incoming.vector)
        if current.deleted || incoming.deleted {
            let winner = incoming.deleted && !current.deleted ? incoming : current
            try persist(copy(winner, vector: vector), identity: identity)
            return
        }
        guard let currentPayload = current.payload, let incomingPayload = incoming.payload else { throw WorkspaceSyncError.invalidChange }
        let old = try JSONFields.object(currentPayload); let new = try JSONFields.object(incomingPayload)
        if incoming.kind == "Artifact", ["hash", "byteCount", "relativePath"].contains(where: { !JSONFields.equal(old[$0], new[$0]) }) {
            throw WorkspaceSyncError.immutableRecordConflict
        }
        if incoming.kind == "Message", old["role"] as? String == "USER", !JSONFields.equal(old["content"], new["content"]) {
            throw WorkspaceSyncError.immutableRecordConflict
        }
        if incoming.kind == "MemoryEntry" || incoming.kind == "ContextSummary" || incoming.kind == "MessageReaction" || incoming.kind == "ConversationParticipant" {
            let currentRemoved = Self.removed(kind: incoming.kind, object: old)
            let incomingRemoved = Self.removed(kind: incoming.kind, object: new)
            let concurrent = !current.vector.dominates(incoming.vector) && !incoming.vector.dominates(current.vector)
            if (incoming.kind == "MemoryEntry" && currentRemoved) || (concurrent && currentRemoved != incomingRemoved) {
                try persist(copy(currentRemoved ? current : incoming, vector: vector), identity: identity)
                return
            }
        }
        if current.vector.dominates(incoming.vector) { return }
        if ["AgentConfigurationRevision", "SkillRevision"].contains(incoming.kind), !Self.sameContent(old, new) {
            throw WorkspaceSyncError.immutableRecordConflict
        }
        if incoming.kind == "ConversationReadPosition" {
            let left = try WorkspaceCoding.decode(BlotV3.ConversationReadPosition.self, from: Data(currentPayload.utf8))
            let right = try WorkspaceCoding.decode(BlotV3.ConversationReadPosition.self, from: Data(incomingPayload.utf8))
            let newer = right.position > left.position || (right.position == left.position && right.messageId.uuidString > left.messageId.uuidString)
            try persist(copy(newer ? incoming : current, vector: vector), identity: identity)
            return
        }
        let concurrent = !incoming.vector.dominates(current.vector)
        if concurrent && ["AgentProfile", "Automation"].contains(incoming.kind) && !Self.sameContent(old, new) {
            try saveConflict(current, identity: identity)
            try saveConflict(incoming, identity: identity)
            let winner = stamp(incoming).wins(over: stamp(current)) ? incoming : current
            try persist(copy(winner, vector: vector), identity: identity)
            return
        }
        var merged = old
        var fields = current.fields
        for (field, candidate) in incoming.fields {
            if fields[field].map({ candidate.wins(over: $0) }) ?? true {
                merged[field] = new[field]
                fields[field] = candidate
            }
        }
        // Metadata is presentation/version state; field causality, rather than wall clocks, resolves edits.
        let winner = stamp(incoming).wins(over: stamp(current)) ? incoming : current
        let winnerJSON = winner.origin == incoming.origin && winner.sequence == incoming.sequence ? new : old
        merged["metadata"] = winnerJSON["metadata"]
        let payload = try JSONFields.string(merged)
        let value = try WorkspaceRecordCodec.decode(kind: incoming.kind, payload: payload)
        try persist(.init(kind: incoming.kind, recordID: incoming.recordID, version: value.metadata.version, payload: value.payload,
            deleted: false, vector: vector, fields: fields, origin: winner.origin, sequence: winner.sequence), identity: identity)
    }

    private func persist(_ record: WorkspaceReplicaRecord, identity: WorkspaceIdentity) throws {
        let decoded = try record.payload.map { try WorkspaceRecordCodec.decode(kind: record.kind, payload: $0) }
        let payload: SQLiteDatabase.Value = decoded.map { .text($0.payload) } ?? .null
        try database.execute("INSERT INTO records(kind, id, workspace_id, version, payload, deleted) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET version = excluded.version, payload = excluded.payload, deleted = excluded.deleted",
            [.text(record.kind), .text(record.recordID.uuidString), .text(identity.workspaceID.uuidString), .integer(Int64(record.version)), payload, .integer(record.deleted ? 1 : 0)])
        try index.update(kind: record.kind, id: record.recordID, workspaceID: identity.workspaceID, content: decoded?.content)
        try saveState(record)
    }

    private func state(kind: String, id: UUID) throws -> WorkspaceReplicaRecord? {
        try database.query("SELECT r.version, r.payload, r.deleted, s.vector, s.fields, s.origin, s.sequence FROM records r JOIN replica_records s ON s.kind = r.kind AND s.id = r.id WHERE r.kind = ? AND r.id = ?",
            [.text(kind), .text(id.uuidString)]) { row in
                guard let origin = UUID(uuidString: SQLiteDatabase.text(row, 5)) else { throw WorkspaceSyncError.invalidChange }
                return WorkspaceReplicaRecord(kind: kind, recordID: id, version: Int(sqlite3_column_int64(row, 0)),
                    payload: sqlite3_column_type(row, 1) == SQLITE_NULL ? nil : SQLiteDatabase.text(row, 1), deleted: sqlite3_column_int(row, 2) != 0,
                    vector: try WorkspaceCoding.decode(WorkspaceVersionVector.self, from: Data(SQLiteDatabase.text(row, 3).utf8)),
                    fields: try WorkspaceCoding.decode([String: WorkspaceFieldStamp].self, from: Data(SQLiteDatabase.text(row, 4).utf8)),
                    origin: origin, sequence: sqlite3_column_int64(row, 6))
            }.first
    }

    private func saveState(_ record: WorkspaceReplicaRecord) throws {
        try database.execute("INSERT INTO replica_records(kind, id, vector, fields, origin, sequence) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET vector = excluded.vector, fields = excluded.fields, origin = excluded.origin, sequence = excluded.sequence",
            [.text(record.kind), .text(record.recordID.uuidString), .text(try jsonString(record.vector)), .text(try jsonString(record.fields)),
             .text(record.origin.uuidString), .integer(record.sequence)])
    }

    private func saveConflict(_ record: WorkspaceReplicaRecord, identity: WorkspaceIdentity) throws {
        guard let payload = record.payload else { return }
        let hash = SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
        let id = WorkspaceLogicalID.make(kind: "ConflictingRevision", workspaceID: identity.workspaceID, parts: [record.kind, record.recordID.uuidString, hash])
        let decoded = try WorkspaceRecordCodec.decode(kind: record.kind, payload: payload)
        let metadata = try BlotV3.RecordMetadata(id: id, ownerId: identity.ownerID, workspaceId: identity.workspaceID, version: 1,
            createdAt: decoded.metadata.updatedAt, updatedAt: decoded.metadata.updatedAt)
        let conflict = try BlotV3.ConflictingRevision(metadata: metadata, recordKind: record.kind, recordId: record.recordID,
            baseVersion: max(0, record.version - 1), originDeviceId: record.origin, payloadJSON: payload, resolved: false)
        if try state(kind: "ConflictingRevision", id: id) == nil {
            let fields = Dictionary(uniqueKeysWithValues: (try JSONFields.object(jsonString(conflict))).keys.filter { $0 != "metadata" }.map {
                ($0, WorkspaceFieldStamp(vector: record.vector, origin: record.origin, sequence: record.sequence))
            })
            try persist(.init(kind: "ConflictingRevision", recordID: id, version: 1, payload: try jsonString(conflict), deleted: false,
                vector: record.vector, fields: fields, origin: record.origin, sequence: record.sequence), identity: identity)
        }
    }

    private func advanceClock(_ origin: UUID, to sequence: Int64) throws {
        try database.execute("INSERT INTO replica_clock(origin, sequence) VALUES (?, ?) ON CONFLICT(origin) DO UPDATE SET sequence = MAX(sequence, excluded.sequence)",
            [.text(origin.uuidString.lowercased()), .integer(sequence)])
    }
    private func stamp(_ record: WorkspaceReplicaRecord) -> WorkspaceFieldStamp { .init(vector: record.vector, origin: record.origin, sequence: record.sequence) }
    private func copy(_ record: WorkspaceReplicaRecord, vector: WorkspaceVersionVector) -> WorkspaceReplicaRecord {
        .init(kind: record.kind, recordID: record.recordID, version: record.version, payload: record.payload, deleted: record.deleted,
            vector: vector, fields: record.fields, origin: record.origin, sequence: record.sequence)
    }
    private static func removed(kind: String, object: [String: Any]) -> Bool {
        if kind == "MemoryEntry" { return object["state"] as? String == "DELETED" }
        if kind == "ContextSummary" { return object["valid"] as? Bool == false }
        return object["removed"] as? Bool == true
    }
    private static func sameContent(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        var left = lhs; var right = rhs; left["metadata"] = nil; right["metadata"] = nil
        return JSONFields.equal(left, right)
    }
    private func jsonString<T: Encodable>(_ value: T) throws -> String { String(decoding: try WorkspaceCoding.encode(value), as: UTF8.self) }
}
