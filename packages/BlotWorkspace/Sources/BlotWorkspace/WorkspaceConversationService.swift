import BlotDomain
import Foundation

public struct WorkspaceConversationService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func update(commandID: UUID, conversationID: UUID, expectedVersion: Int, title: String? = nil,
                       pinned: Bool? = nil, archived: Bool? = nil, now: Date = Date()) async throws {
        struct Input: Encodable {
            let type = "conversation.update"
            let workspaceID: UUID; let conversationID: UUID; let expectedVersion: Int
            let title: String?; let pinned: Bool?; let archived: Bool?
        }
        let input = try WorkspaceCoding.encode(Input(workspaceID: identity.workspaceID, conversationID: conversationID,
            expectedVersion: expectedVersion, title: title, pinned: pinned, archived: archived))
        _ = try await repository.execute(commandID: commandID, command: input, identity: identity, legacyResultID: conversationID) { tx in
            let chat = try tx.require(BlotV3.Conversation.self, id: conversationID, version: expectedVersion)
            if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw WorkspaceStorageError.invalidRecord }
            let conversations = try tx.records(BlotV3.Conversation.self)
            let index = WorkspaceDirectConversations(conversations)
            for member in conversations where index.canonicalID(member.metadata.id) == index.canonicalID(chat.metadata.id) {
                let updated = try BlotV3.Conversation(metadata: tx.metadata(id: member.metadata.id, now: now, replacing: member.metadata),
                    agentId: member.agentId, title: member.metadata.id == conversationID ? title ?? member.title : member.title,
                    mobileOwned: member.mobileOwned, pinned: pinned ?? member.pinned, archived: archived ?? member.archived, kind: member.kind)
                try tx.put(updated, expectedVersion: member.metadata.version)
            }
            return conversationID
        }
    }

    public func delete(commandID: UUID, conversationID: UUID, expectedVersion: Int) async throws {
        struct Input: Encodable {
            let type = "conversation.delete"
            let workspaceID: UUID; let conversationID: UUID; let expectedVersion: Int
        }
        let input = try WorkspaceCoding.encode(Input(workspaceID: identity.workspaceID, conversationID: conversationID, expectedVersion: expectedVersion))
        _ = try await repository.execute(commandID: commandID, command: input, identity: identity, legacyResultID: conversationID) { tx in
            _ = try tx.require(BlotV3.Conversation.self, id: conversationID, version: expectedVersion)
            let conversations = try tx.records(BlotV3.Conversation.self)
            let index = WorkspaceDirectConversations(conversations)
            let family = Set(conversations.filter { index.canonicalID($0.metadata.id) == index.canonicalID(conversationID) }.map(\.metadata.id))
            let messages = try tx.records(BlotV3.Message.self).filter { family.contains($0.conversationId) }
            let ids = Set(messages.map(\.metadata.id))
            for record in try tx.records(BlotV3.MessageReaction.self) where ids.contains(record.messageId) { try tx.delete(record) }
            for record in try tx.records(BlotV3.ConversationParticipant.self) where family.contains(record.conversationId) { try tx.delete(record) }
            for record in try tx.records(BlotV3.ConversationReadPosition.self) where family.contains(record.conversationId) { try tx.delete(record) }
            for record in try tx.records(BlotV3.ContextSummary.self) where family.contains(record.conversationId) { try tx.delete(record) }
            for message in messages { try tx.delete(message) }
            for conversation in conversations where family.contains(conversation.metadata.id) { try tx.delete(conversation) }
            return conversationID
        }
    }
}
