import Foundation

final class WorkspaceRecordIndex {
    private let database: SQLiteDatabase
    init(database: SQLiteDatabase) { self.database = database }

    func update(kind: String, id: UUID, workspaceID: UUID, content: String?) throws {
        guard kind == "Message" else { return }
        try database.execute("DELETE FROM message_search WHERE record_id = ?", [.text(id.uuidString)])
        if let content {
            try database.execute("INSERT INTO message_search(record_id, workspace_id, content) VALUES (?, ?, ?)",
                [.text(id.uuidString), .text(workspaceID.uuidString), .text(content)])
        }
    }
}
