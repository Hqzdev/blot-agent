import BlotDomain
import CryptoKit
import CSQLite
import Foundation

/// Persists records, receipts and pending replication changes in the same SQLite transaction.
public actor WorkspaceRepository {
    private let database: SQLiteDatabase
    private let store: WorkspaceRecordStore
    private let replicas: WorkspaceReplicaStore

    public init(url: URL) throws {
        let database = try SQLiteDatabase(url: url)
        self.database = database
        self.store = WorkspaceRecordStore(database: database)
        self.replicas = WorkspaceReplicaStore(database: database)
    }

    /// Stop callers first. Explicit close permits safe backup/deletion without unlinking an open WAL.
    public func close() throws { try database.close(); for observer in observers.values { observer.finish() }; observers = [:] }

    private struct LocalSnapshotRequest: Codable {
        let cursor: Int64
        var completed: Bool
    }
    func snapshotRequestCursor(id: UUID) throws -> Int64 {
        try database.transaction {
            let key = "snapshot-request:" + id.uuidString
            if let saved = try database.query("SELECT value FROM local_settings WHERE key = ?", [.text(key)], row: { SQLiteDatabase.text($0, 0) }).first {
                return try WorkspaceCoding.decode(LocalSnapshotRequest.self, from: Data(saved.utf8)).cursor
            }
            let cursor = try relayCursor()
            let value = try WorkspaceCoding.encode(LocalSnapshotRequest(cursor: cursor, completed: false))
            try database.execute("INSERT INTO local_settings(key,value) VALUES (?,?)", [.text(key), .text(String(decoding: value, as: UTF8.self))])
            return cursor
        }
    }
    func pendingSnapshotRequestIDs() throws -> [UUID] {
        try database.query("SELECT key,value FROM local_settings WHERE key LIKE 'snapshot-request:%'") { row -> UUID? in
            let saved = try WorkspaceCoding.decode(LocalSnapshotRequest.self, from: Data(SQLiteDatabase.text(row, 1).utf8))
            return saved.completed ? nil : UUID(uuidString: String(SQLiteDatabase.text(row, 0).dropFirst("snapshot-request:".count)))
        }.compactMap { $0 }
    }
    func completeSnapshotRequest(id: UUID) throws {
        let key = "snapshot-request:" + id.uuidString
        try database.transaction {
            guard let saved = try database.query("SELECT value FROM local_settings WHERE key = ?", [.text(key)], row: { SQLiteDatabase.text($0, 0) }).first else {
                throw WorkspaceStorageError.missingRecord
            }
            var state = try WorkspaceCoding.decode(LocalSnapshotRequest.self, from: Data(saved.utf8))
            state.completed = true
            let value = try WorkspaceCoding.encode(state)
            try database.execute("UPDATE local_settings SET value = ? WHERE key = ?", [.text(String(decoding: value, as: UTF8.self)), .text(key)])
        }
    }

    public func accountIdentity(ownerID: UUID, workspaceID: UUID) throws -> WorkspaceIdentity {
        try database.transaction {
            if let json = try database.query("SELECT value FROM local_settings WHERE key = 'identity'", row: { SQLiteDatabase.text($0, 0) }).first {
                let identity = try WorkspaceCoding.decode(WorkspaceIdentity.self, from: Data(json.utf8))
                guard identity.ownerID == ownerID, identity.workspaceID == workspaceID else { throw WorkspaceSyncError.identityMismatch }
                return identity
            }
            guard try database.query("SELECT COUNT(*) FROM records", row: { SQLiteDatabase.text($0, 0) }).first == "0" else {
                throw WorkspaceSyncError.identityMismatch
            }
            let identity = WorkspaceIdentity(ownerID: ownerID, workspaceID: workspaceID, deviceID: UUID())
            let json = String(decoding: try WorkspaceCoding.encode(identity), as: UTF8.self)
            try database.execute("INSERT INTO local_settings(key, value) VALUES ('identity', ?)", [.text(json)])
            return identity
        }
    }

    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in _Concurrency.Task { await self?.removeObserver(id) } }
        pair.continuation.yield(())
        return pair.stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private func publishChanges() { for observer in observers.values { observer.yield(()) } }

    public func presentationState() throws -> Data? {
        try database.query("SELECT value FROM local_settings WHERE key = 'presentation-state'", row: { Data(SQLiteDatabase.text($0, 0).utf8) }).first
    }
    public func savePresentationState(_ data: Data) throws {
        guard data.count <= 1_048_576, String(data: data, encoding: .utf8) != nil else { throw WorkspaceStorageError.invalidParameters }
        try database.execute("INSERT INTO local_settings(key,value) VALUES ('presentation-state',?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [.text(String(decoding: data, as: UTF8.self))])
    }

    public func localIdentity() throws -> WorkspaceIdentity {
        try database.transaction {
            if let json = try database.query("SELECT value FROM local_settings WHERE key = 'identity'", row: { SQLiteDatabase.text($0, 0) }).first {
                return try WorkspaceCoding.decode(WorkspaceIdentity.self, from: Data(json.utf8))
            }
            let identity = WorkspaceIdentity(ownerID: UUID(), workspaceID: UUID(), deviceID: UUID())
            let json = String(decoding: try WorkspaceCoding.encode(identity), as: UTF8.self)
            try database.execute("INSERT INTO local_settings(key, value) VALUES ('identity', ?)", [.text(json)])
            return identity
        }
    }

    public func records<T: BlotWorkspaceRecord>(_ type: T.Type, workspaceID: UUID) throws -> [T] {
        try store.records(type, workspaceID: workspaceID)
    }

    public func record<T: BlotWorkspaceRecord>(_ type: T.Type, id: UUID, workspaceID: UUID) throws -> T? {
        try store.record(type, id: id, workspaceID: workspaceID)
    }

    public func projection(identity: WorkspaceIdentity) throws -> WorkspaceProjection {
        try database.transaction {
            var result = WorkspaceProjection()
            result.agents = try store.records(BlotV3.AgentProfile.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.configurations = try store.records(BlotV3.AgentConfigurationRevision.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.conversations = try store.records(BlotV3.Conversation.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.messages = try store.records(BlotV3.Message.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.participants = try store.records(BlotV3.ConversationParticipant.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.reactions = try store.records(BlotV3.MessageReaction.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.readPositions = try store.records(BlotV3.ConversationReadPosition.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.schedules = try store.records(BlotV3.Automation.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.automationRuns = try store.records(BlotV3.AutomationRun.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.memories = try store.records(BlotV3.MemoryEntry.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.summaries = try store.records(BlotV3.ContextSummary.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.skills = try store.records(BlotV3.Skill.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.skillRevisions = try store.records(BlotV3.SkillRevision.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.artifacts = try store.records(BlotV3.Artifact.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.connections = try store.records(BlotV3.Connection.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.modelSteps = try store.records(BlotV3.ModelStep.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.tasks = try store.records(BlotV3.Task.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.sessions = try store.records(BlotV3.AgentSession.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.agentMessages = try store.records(BlotV3.AgentMessage.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.actions = try store.records(BlotV3.PreparedAction.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.grants = try store.records(BlotV3.ApprovalGrant.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.invocations = try store.records(BlotV3.ToolInvocation.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.budgets = try store.records(BlotV3.BudgetLedger.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            result.conflicts = try store.records(BlotV3.ConflictingRevision.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
            return result
        }
    }

    public func hasReceipt(commandID: UUID, command: Data) throws -> Bool {
        guard let fingerprint = try database.query("SELECT fingerprint FROM receipts WHERE command_id = ?", [.text(commandID.uuidString)], row: { SQLiteDatabase.text($0, 0) }).first else { return false }
        guard fingerprint == Self.fingerprint(command) else { throw WorkspaceStorageError.commandConflict }
        return true
    }

    /// Returns false for an identical replay. A changed payload for the same ID is always rejected.
    @discardableResult
    public func commit(commandID: UUID, command: Data, mutations: [WorkspaceRecordMutation]) throws -> Bool {
        defer { publishChanges() }
        return try database.transaction {
            if try hasReceipt(commandID: commandID, command: command) { return false }
            try database.execute("INSERT INTO receipts(command_id, fingerprint) VALUES (?, ?)",
                [.text(commandID.uuidString), .text(Self.fingerprint(command))])
            for mutation in mutations { try store.write(mutation, commandID: commandID) }
            return true
        }
    }

    /// Reads, invariants, mutations and replay result share one write transaction.
    public func execute(commandID: UUID, command: Data, identity: WorkspaceIdentity, legacyResultID: UUID? = nil,
                        body: @Sendable (WorkspaceTransaction) throws -> UUID) throws -> UUID {
        try executeOutcome(commandID: commandID, command: command, identity: identity, legacyResultID: legacyResultID, body: body).resultID
    }

    public func executeOutcome(commandID: UUID, command: Data, identity: WorkspaceIdentity, legacyResultID: UUID? = nil,
                        body: @Sendable (WorkspaceTransaction) throws -> UUID) throws -> WorkspaceCommandOutcome {
        defer { publishChanges() }
        return try database.transaction {
            if try hasReceipt(commandID: commandID, command: command) {
                guard let result = try database.query("SELECT result_id FROM receipts WHERE command_id = ?",
                    [.text(commandID.uuidString)], row: { SQLiteDatabase.text($0, 0) }).first,
                    let id = UUID(uuidString: result) else {
                    if let legacyResultID { return .init(resultID: legacyResultID, applied: false) }
                    throw WorkspaceStorageError.invalidRecord
                }
                return .init(resultID: id, applied: false)
            }
            try database.execute("INSERT INTO receipts(command_id, fingerprint) VALUES (?, ?)",
                [.text(commandID.uuidString), .text(Self.fingerprint(command))])
            let transaction = WorkspaceTransaction(store: store, identity: identity, commandID: commandID)
            defer { transaction.close() }
            let id = try body(transaction)
            try database.execute("UPDATE receipts SET result_id = ? WHERE command_id = ?",
                [.text(id.uuidString), .text(commandID.uuidString)])
            return .init(resultID: id, applied: true)
        }
    }

    public func pendingChanges(limit: Int = 100) throws -> [PendingWorkspaceChange] {
        try database.query("SELECT sequence, change_id, command_id, kind, record_id, version, payload, deleted FROM outbox WHERE acknowledged = 0 ORDER BY sequence LIMIT ?",
            [.integer(Int64(max(1, min(limit, 500))))]) { row in
                guard let changeID = UUID(uuidString: SQLiteDatabase.text(row, 1)),
                      let commandID = UUID(uuidString: SQLiteDatabase.text(row, 2)),
                      let recordID = UUID(uuidString: SQLiteDatabase.text(row, 4)) else { throw WorkspaceStorageError.invalidRecord }
                return PendingWorkspaceChange(sequence: sqlite3_column_int64(row, 0), changeID: changeID,
                    commandID: commandID, kind: SQLiteDatabase.text(row, 3), recordID: recordID,
                    version: Int(sqlite3_column_int64(row, 5)),
                    payload: sqlite3_column_type(row, 6) == SQLITE_NULL ? nil : SQLiteDatabase.text(row, 6),
                    deleted: sqlite3_column_int(row, 7) != 0)
            }
    }

    public func searchMessages(_ query: String, workspaceID: UUID, limit: Int = 50) throws -> [BlotV3.Message] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        guard !words.isEmpty else { return [] }
        return try database.query("""
            SELECT r.payload FROM message_search s JOIN records r ON r.id = s.record_id AND r.kind = 'Message'
            WHERE message_search MATCH ? AND s.workspace_id = ? AND r.deleted = 0
            ORDER BY rank LIMIT ?
            """, [.text(words.joined(separator: " AND ")), .text(workspaceID.uuidString), .integer(Int64(max(1, min(limit, 500))))]) {
                try WorkspaceCoding.decode(BlotV3.Message.self, from: Data(SQLiteDatabase.text($0, 0).utf8))
            }
    }

    public func joinWorkspace(ownerID: UUID, workspaceID: UUID) throws -> WorkspaceIdentity {
        try database.transaction {
            let count = try database.query("SELECT COUNT(*) FROM records", row: { sqlite3_column_int64($0, 0) }).first ?? 0
            guard count == 0 else { throw WorkspaceSyncError.identityMismatch }
            let old = try database.query("SELECT value FROM local_settings WHERE key = 'identity'", row: { SQLiteDatabase.text($0, 0) }).first
            let deviceID = try old.map { try WorkspaceCoding.decode(WorkspaceIdentity.self, from: Data($0.utf8)).deviceID } ?? UUID()
            let identity = WorkspaceIdentity(ownerID: ownerID, workspaceID: workspaceID, deviceID: deviceID)
            try database.execute("INSERT INTO local_settings(key, value) VALUES ('identity', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [.text(String(decoding: try WorkspaceCoding.encode(identity), as: UTF8.self))])
            return identity
        }
    }

    public func pendingSyncChanges(limit: Int = 100) throws -> [WorkspaceSyncChange] {
        try database.query("SELECT change_id, workspace_id, owner_id, origin_device, sequence, kind, record_id, version, payload, deleted, vector, changed_fields, occurred_at FROM outbox WHERE acknowledged = 0 ORDER BY sequence LIMIT ?",
            [.integer(Int64(max(1, min(limit, 500))))]) { row in
                guard let changeID = UUID(uuidString: SQLiteDatabase.text(row, 0)), let workspaceID = UUID(uuidString: SQLiteDatabase.text(row, 1)),
                      let ownerID = UUID(uuidString: SQLiteDatabase.text(row, 2)), let origin = UUID(uuidString: SQLiteDatabase.text(row, 3)),
                      let recordID = UUID(uuidString: SQLiteDatabase.text(row, 6)), let date = ISO8601DateFormatter().date(from: SQLiteDatabase.text(row, 12)) else {
                    throw WorkspaceSyncError.invalidChange
                }
                return WorkspaceSyncChange(changeID: changeID, workspaceID: workspaceID, ownerID: ownerID, originDeviceID: origin,
                    sequence: sqlite3_column_int64(row, 4), kind: SQLiteDatabase.text(row, 5), recordID: recordID,
                    version: Int(sqlite3_column_int64(row, 7)), payload: sqlite3_column_type(row, 8) == SQLITE_NULL ? nil : SQLiteDatabase.text(row, 8),
                    deleted: sqlite3_column_int(row, 9) != 0,
                    vector: try WorkspaceCoding.decode(WorkspaceVersionVector.self, from: Data(SQLiteDatabase.text(row, 10).utf8)),
                    changedFields: try WorkspaceCoding.decode([String].self, from: Data(SQLiteDatabase.text(row, 11).utf8)), occurredAt: date)
            }
    }

    /// Freeze plaintext before encryption. Later streaming writes cannot mutate a claimed nonce/sequence.
    public func claimSyncChanges(limit: Int = 100) throws -> [WorkspaceSyncChange] {
        try database.transaction {
            let changes = try pendingSyncChanges(limit: limit)
            for change in changes {
                try database.execute("UPDATE outbox SET in_flight = 1 WHERE change_id = ?", [.text(change.changeID.uuidString)])
            }
            return changes
        }
    }

    public func applySyncChanges(_ changes: [WorkspaceSyncChange], identity: WorkspaceIdentity, relayCursor: Int64) throws {
        defer { if !changes.isEmpty { publishChanges() } }
        guard relayCursor >= 0 else { throw WorkspaceSyncError.invalidChange }
        try database.transaction {
            for change in changes { try replicas.apply(change, identity: identity) }
            try database.execute("INSERT INTO replica_state(key, value) VALUES ('relay_cursor', ?) ON CONFLICT(key) DO UPDATE SET value = MAX(value, excluded.value)", [.integer(relayCursor)])
        }
    }

    public func relayCursor() throws -> Int64 {
        try database.query("SELECT value FROM replica_state WHERE key = 'relay_cursor'", row: { sqlite3_column_int64($0, 0) }).first ?? 0
    }

    public func replicaSnapshot(identity: WorkspaceIdentity) throws -> WorkspaceReplicaSnapshot {
        try database.transaction {
            // A snapshot publishes these versions too; later deltas need a new sequence.
            try database.execute("UPDATE outbox SET in_flight = 1 WHERE acknowledged = 0")
            return try replicas.snapshot(identity: identity, cursor: relayCursor())
        }
    }

    public func installReplicaSnapshot(_ snapshot: WorkspaceReplicaSnapshot, identity: WorkspaceIdentity) throws {
        defer { publishChanges() }
        try database.transaction {
            try replicas.install(snapshot, identity: identity)
            try database.execute("INSERT INTO replica_state(key, value) VALUES ('relay_cursor', ?) ON CONFLICT(key) DO UPDATE SET value = MAX(value, excluded.value)", [.integer(snapshot.relayCursor)])
        }
    }

    public func acknowledgeOutbox(_ changeIDs: [UUID]) throws {
        try database.transaction {
            for id in changeIDs { try database.execute("UPDATE outbox SET acknowledged = 1 WHERE change_id = ?", [.text(id.uuidString)]) }
        }
    }

    public func encryptedOutboxPacket(changeID: UUID) throws -> WorkspaceEncryptedPacket? {
        try database.query("SELECT packet FROM sealed_outbox WHERE change_id = ?", [.text(changeID.uuidString)]) {
            try WorkspaceCoding.decode(WorkspaceEncryptedPacket.self, from: Data(SQLiteDatabase.text($0, 0).utf8))
        }.first
    }

    public func cacheEncryptedOutboxPacket(_ packet: WorkspaceEncryptedPacket) throws -> WorkspaceEncryptedPacket {
        try database.transaction {
            let source = try database.query("SELECT origin_device, sequence, workspace_id FROM outbox WHERE change_id = ? AND in_flight = 1",
                [.text(packet.changeID.uuidString)]) { (SQLiteDatabase.text($0, 0), sqlite3_column_int64($0, 1), SQLiteDatabase.text($0, 2)) }.first
            guard let source, source.0 == packet.originDeviceID.uuidString, source.1 == packet.sequence,
                  source.2 == packet.workspaceID.uuidString, packet.kind == .change else { throw WorkspaceSyncError.identityMismatch }
            if let old = try encryptedOutboxPacket(changeID: packet.changeID) {
                if old.keyEpoch == packet.keyEpoch {
                    guard old.ciphertext == packet.ciphertext else { throw WorkspaceSyncError.replayConflict }
                    return old
                }
                guard packet.keyEpoch > old.keyEpoch else { throw WorkspaceSyncError.unknownKeyEpoch }
            }
            try database.execute("INSERT INTO sealed_outbox(change_id, epoch, packet) VALUES (?, ?, ?) ON CONFLICT(change_id) DO UPDATE SET epoch = excluded.epoch, packet = excluded.packet",
                [.text(packet.changeID.uuidString), .integer(packet.keyEpoch), .text(String(decoding: try WorkspaceCoding.encode(packet), as: UTF8.self))])
            return packet
        }
    }

    private static func fingerprint(_ command: Data) -> String {
        SHA256.hash(data: command).map { String(format: "%02x", $0) }.joined()
    }
}
