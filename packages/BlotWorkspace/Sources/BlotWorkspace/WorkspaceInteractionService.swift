import BlotDomain
import Foundation

public struct WorkspaceInteractionService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func setReaction(commandID: UUID, messageID: UUID, emoji: String, removed: Bool,
                            replacingOtherReactions: Bool = false, now: Date = Date()) async throws {
        struct Input: Encodable { let messageID: UUID; let emoji: String; let removed: Bool; let replacingOtherReactions: Bool }
        let command = try WorkspaceCommand(type: "message.reaction.set", workspaceID: identity.workspaceID,
            payload: Input(messageID: messageID, emoji: emoji, removed: removed, replacingOtherReactions: replacingOtherReactions)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            guard !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, emoji.count <= 8 else { throw WorkspaceStorageError.invalidParameters }
            let source = try tx.require(BlotV3.Message.self, id: messageID)
            _ = try tx.require(BlotV3.Conversation.self, id: source.conversationId)
            if replacingOtherReactions && !removed {
                for old in try tx.records(BlotV3.MessageReaction.self) where old.messageId == messageID && old.participantId == tx.identity.ownerID && !old.removed && old.emoji != emoji {
                    try Self.put(tx, old: old, messageID: messageID, emoji: old.emoji, removed: true, now: now)
                }
            }
            let id = WorkspaceLogicalID.make(kind: "MessageReaction", workspaceID: tx.identity.workspaceID,
                parts: [messageID.uuidString, tx.identity.ownerID.uuidString, emoji])
            let old = try tx.record(BlotV3.MessageReaction.self, id: id)
            if old?.removed != removed { try Self.put(tx, old: old, messageID: messageID, emoji: emoji, removed: removed, now: now) }
            return messageID
        }
    }

    public func markRead(commandID: UUID, conversationID: UUID, messageID: UUID, now: Date = Date()) async throws {
        struct Input: Encodable { let conversationID: UUID; let messageID: UUID }
        let command = try WorkspaceCommand(type: "conversation.read", workspaceID: identity.workspaceID,
            payload: Input(conversationID: conversationID, messageID: messageID)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            _ = try tx.require(BlotV3.Conversation.self, id: conversationID)
            let messages = WorkspaceMessageOrder.ordered(try tx.records(BlotV3.Message.self).filter { $0.conversationId == conversationID })
            guard let index = messages.firstIndex(where: { $0.metadata.id == messageID }) else { throw WorkspaceStorageError.invalidRecord }
            let id = WorkspaceLogicalID.make(kind: "ConversationReadPosition", workspaceID: tx.identity.workspaceID,
                parts: [conversationID.uuidString, tx.identity.ownerID.uuidString])
            let old = try tx.record(BlotV3.ConversationReadPosition.self, id: id)
            let source = messages[index]
            let position = source.position ?? index + 1
            guard WorkspaceMessageOrder.isAfter(source, legacyPosition: index + 1, read: old) else { return id }
            let record = try BlotV3.ConversationReadPosition(metadata: tx.metadata(id: id, now: now, replacing: old?.metadata),
                conversationId: conversationID, participantId: tx.identity.ownerID, messageId: messageID, position: position)
            try tx.put(record, expectedVersion: old?.metadata.version ?? 0)
            return id
        }
    }

    private static func put(_ tx: WorkspaceTransaction, old: BlotV3.MessageReaction?, messageID: UUID, emoji: String, removed: Bool, now: Date) throws {
        let id = old?.metadata.id ?? WorkspaceLogicalID.make(kind: "MessageReaction", workspaceID: tx.identity.workspaceID,
            parts: [messageID.uuidString, tx.identity.ownerID.uuidString, emoji])
        let reaction = try BlotV3.MessageReaction(metadata: tx.metadata(id: id, now: now, replacing: old?.metadata),
            messageId: messageID, participantId: tx.identity.ownerID, emoji: emoji, removed: removed)
        try tx.put(reaction, expectedVersion: old?.metadata.version ?? 0)
    }
}
