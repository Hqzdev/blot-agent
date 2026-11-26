import BlotDomain
import Foundation

/// Optional snapshot metadata follows the same compatibility boundary as message pins.
/// Missing metadata from a legacy device never erases a card. Only its executor can consume a response.
final class WorkspaceCardSnapshotStore {
    private let database: SQLiteDatabase
    init(database: SQLiteDatabase) { self.database = database }

    func records(identity: WorkspaceIdentity) throws -> [BlotV3.ConversationCard] {
        try WorkspaceRecordStore(database: database).records(BlotV3.ConversationCard.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
    }
    func merge(_ incoming: [BlotV3.ConversationCard], identity: WorkspaceIdentity) throws {
        guard incoming.count <= 10_000, Set(incoming.map { $0.metadata.id }).count == incoming.count else { throw WorkspaceSyncError.invalidSnapshot }
        let store = WorkspaceRecordStore(database: database)
        // Message tombstones remain the authority when an older client deletes a conversation.
        try database.execute("UPDATE records SET payload = NULL, deleted = 1 WHERE kind = 'ConversationCard' AND workspace_id = ? AND EXISTS (SELECT 1 FROM records m WHERE m.kind = 'Message' AND m.id = json_extract(records.payload, '$.messageId') AND m.deleted = 1)", [.text(identity.workspaceID.uuidString)])
        for card in incoming {
            guard card.metadata.ownerId == identity.ownerID, card.metadata.workspaceId == identity.workspaceID,
                  card.metadata.version > 0, card.payloadJSON.utf8.count <= 48 * 1024,
                  (card.responseJSON?.utf8.count ?? 0) <= 64 * 1024,
                  card.state != "consumed" || card.updatedByDeviceId == card.executorDeviceId else { throw WorkspaceSyncError.invalidSnapshot }
            guard ["pending", "answered", "consumed"].contains(card.state),
                  let content = try? JSONDecoder().decode(WorkspaceCardContent.self, from: Data(card.payloadJSON.utf8)), content.kind == card.kind else { continue }
            if let raw = card.responseJSON {
                let response = try JSONDecoder().decode(WorkspaceCardResponse.self, from: Data(raw.utf8))
                if card.kind == "subscription", response.action == "payment_status", let value = response.value {
                    let payment = try JSONDecoder().decode(WorkspaceSubscriptionPayment.self, from: Data(value.utf8))
                    guard payment.test, ["premium", "super", "ultra"].contains(payment.plan), ["pending", "waiting_for_capture", "succeeded", "canceled"].contains(payment.status) else { throw WorkspaceSyncError.invalidSnapshot }
                } else { try WorkspaceConversationCardService.validate(response, for: content) }
            } else if card.state != "pending" { throw WorkspaceSyncError.invalidSnapshot }
            let message = try database.query("SELECT deleted FROM records WHERE kind = 'Message' AND id = ? AND workspace_id = ?", [.text(card.messageId.uuidString), .text(identity.workspaceID.uuidString)]) { SQLiteDatabase.text($0, 0) }.first
            guard let message, message == "0" else { continue }
            if let old = try store.record(BlotV3.ConversationCard.self, id: card.metadata.id, workspaceID: identity.workspaceID) {
                guard old.metadata.ownerId == identity.ownerID, old.messageId == card.messageId, old.operationId == card.operationId, old.executorDeviceId == card.executorDeviceId,
                      old.kind == card.kind, old.payloadJSON == card.payloadJSON, old.expiresAt == card.expiresAt,
                      old.metadata.createdAt == card.metadata.createdAt else { throw WorkspaceSyncError.invalidSnapshot }
                if old.state == "consumed" { continue }
                if old.state == "answered", card.state == "pending" { continue }
                guard card.state == "consumed" || card.metadata.version > old.metadata.version ||
                    (card.metadata.version == old.metadata.version && card.updatedByDeviceId.uuidString > old.updatedByDeviceId.uuidString) else { continue }
            } else {
                let existing = try database.query("SELECT workspace_id,deleted FROM records WHERE kind = 'ConversationCard' AND id = ?", [.text(card.metadata.id.uuidString)]) { (SQLiteDatabase.text($0, 0), SQLiteDatabase.text($0, 1)) }.first
                guard existing.map({ $0.0 == identity.workspaceID.uuidString }) ?? true else { throw WorkspaceSyncError.identityMismatch }
                if existing?.1 == "1" { continue }
            }
            let payload = String(decoding: try WorkspaceCoding.encode(card), as: UTF8.self)
            try database.execute("INSERT INTO records(kind,id,workspace_id,version,payload,deleted) VALUES ('ConversationCard',?,?,?,?,0) ON CONFLICT(kind,id) DO UPDATE SET version = excluded.version, payload = excluded.payload, deleted = 0", [.text(card.metadata.id.uuidString), .text(identity.workspaceID.uuidString), .integer(Int64(card.metadata.version)), .text(payload)])
        }
    }
}
