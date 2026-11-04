import CSQLite
import Foundation

public enum WorkspaceStorageError: Error, Equatable, Sendable {
    case sqlite(Int32)
    case unsupportedDatabase(Int)
    case databaseClosed
    case commandConflict
    case versionConflict
    case unresolvedConflict
    case deletedRecord
    case invalidRecord
    case missingConversation
    case missingRecord
    case permissionDenied
    case transactionClosed
    case invalidParameters
}

/// Owned by one repository actor. SQL errors expose codes, never record contents or secrets.
final class SQLiteDatabase {
    enum Value {
        case text(String), integer(Int64), null
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            throw WorkspaceStorageError.sqlite(code)
        }
        do {
            sqlite3_busy_timeout(handle, 5_000)
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = FULL")
            try migrate()
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func close() throws {
        guard let handle else { return }
        let result = sqlite3_close(handle)
        guard result == SQLITE_OK else { throw WorkspaceStorageError.sqlite(result) }
        self.handle = nil
    }

    func execute(_ sql: String, _ bindings: [Value] = []) throws {
        try query(sql, bindings) { _ in () }
    }

    @discardableResult
    func query<T>(_ sql: String, _ bindings: [Value] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
        guard let handle else { throw WorkspaceStorageError.databaseClosed }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw WorkspaceStorageError.sqlite(prepared) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in bindings.enumerated() {
            let code: Int32
            switch value {
            case .text(let text): code = sqlite3_bind_text(statement, Int32(index + 1), text, -1, transient)
            case .integer(let number): code = sqlite3_bind_int64(statement, Int32(index + 1), number)
            case .null: code = sqlite3_bind_null(statement, Int32(index + 1))
            }
            guard code == SQLITE_OK else { throw WorkspaceStorageError.sqlite(code) }
        }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(try row(statement))
            case SQLITE_DONE: return rows
            case let code: throw WorkspaceStorageError.sqlite(code)
            }
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    static func text(_ row: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(row, column).map { String(cString: $0) } ?? ""
    }

    private func migrate() throws {
        try transaction {
            let version = try query("PRAGMA user_version") { Int(sqlite3_column_int($0, 0)) }.first ?? 0
            guard version <= 4 else { throw WorkspaceStorageError.unsupportedDatabase(version) }
            if version == 0 {
            try execute("""
                CREATE TABLE records (
                    kind TEXT NOT NULL, id TEXT NOT NULL, workspace_id TEXT NOT NULL,
                    version INTEGER NOT NULL, payload TEXT, deleted INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (kind, id)
                )
                """)
            try execute("CREATE TABLE receipts (command_id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL)")
            try execute("""
                CREATE TABLE outbox (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT, change_id TEXT NOT NULL UNIQUE,
                    command_id TEXT NOT NULL, kind TEXT NOT NULL, record_id TEXT NOT NULL,
                    version INTEGER NOT NULL, payload TEXT, deleted INTEGER NOT NULL,
                    acknowledged INTEGER NOT NULL DEFAULT 0,
                    FOREIGN KEY(command_id) REFERENCES receipts(command_id)
                )
                """)
            try execute("CREATE VIRTUAL TABLE message_search USING fts5(record_id UNINDEXED, workspace_id UNINDEXED, content, tokenize='unicode61')")
            try execute("CREATE TABLE local_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            }
            if version < 2 {
                try execute("ALTER TABLE receipts ADD COLUMN result_id TEXT")
            }
            if version < 3 { try WorkspaceReplicationSchema.install(self) }
            if version < 4 { try execute("ALTER TABLE outbox ADD COLUMN in_flight INTEGER NOT NULL DEFAULT 0") }
            try execute("PRAGMA user_version = 4")
        }
    }
}
