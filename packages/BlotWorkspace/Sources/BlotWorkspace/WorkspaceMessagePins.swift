import BlotDomain
import Foundation

/// Pin tombstones and Lamport counters merge independently of message authorship.
public struct WorkspaceMessagePin: Codable, Equatable, Sendable {
    public let conversationID: UUID
    public let messageID: UUID
    public let pinned: Bool
    public let counter: Int64
    public let deviceID: UUID
}

final class WorkspaceMessagePinStore {
    private let database: SQLiteDatabase
    private static let prefix = "message-pin:"

    init(database: SQLiteDatabase) { self.database = database }

    func states() throws -> [WorkspaceMessagePin] {
        try database.query("SELECT value FROM local_settings WHERE key LIKE 'message-pin:%'") {
            try WorkspaceCoding.decode(WorkspaceMessagePin.self, from: Data(SQLiteDatabase.text($0, 0).utf8))
        }.sorted { $0.messageID.uuidString < $1.messageID.uuidString }
    }

    func set(message: BlotV3.Message, pinned: Bool, identity: WorkspaceIdentity) throws {
        let known = try states()
        if known.first(where: { $0.messageID == message.metadata.id })?.pinned == pinned { return }
        let counter = known.map(\.counter).max() ?? 0
        guard counter < Int64.max - 1 else { throw WorkspaceSyncError.invalidChange }
        try save(.init(conversationID: message.conversationId, messageID: message.metadata.id,
            pinned: pinned, counter: counter + 1, deviceID: identity.deviceID))
    }

    func merge(_ incoming: [WorkspaceMessagePin], identity: WorkspaceIdentity) throws {
        guard Set(incoming.map(\.messageID)).count == incoming.count else { throw WorkspaceSyncError.invalidSnapshot }
        let known = Dictionary(uniqueKeysWithValues: try states().map { ($0.messageID, $0) })
        for pin in incoming {
            guard pin.counter > 0, pin.counter < Int64.max else { throw WorkspaceSyncError.invalidSnapshot }
            if let message = try database.query("SELECT workspace_id, payload FROM records WHERE kind = 'Message' AND id = ? AND deleted = 0",
                [.text(pin.messageID.uuidString)], row: { (SQLiteDatabase.text($0, 0), SQLiteDatabase.text($0, 1)) }).first {
                let value = try WorkspaceCoding.decode(BlotV3.Message.self, from: Data(message.1.utf8))
                guard message.0 == identity.workspaceID.uuidString, value.conversationId == pin.conversationID,
                      value.metadata.ownerId == identity.ownerID else { throw WorkspaceSyncError.identityMismatch }
            }
            if let old = known[pin.messageID] {
                guard old.conversationID == pin.conversationID else { throw WorkspaceSyncError.identityMismatch }
                if old.counter == pin.counter && old.deviceID == pin.deviceID {
                    guard old == pin else { throw WorkspaceSyncError.replayConflict }
                    continue
                }
                guard pin.counter > old.counter || (pin.counter == old.counter && pin.deviceID.uuidString > old.deviceID.uuidString) else { continue }
            }
            try save(pin)
        }
    }

    private func save(_ pin: WorkspaceMessagePin) throws {
        let data = try WorkspaceCoding.encode(pin)
        try database.execute("INSERT INTO local_settings(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            [.text(Self.prefix + pin.messageID.uuidString), .text(String(decoding: data, as: UTF8.self))])
    }
}
