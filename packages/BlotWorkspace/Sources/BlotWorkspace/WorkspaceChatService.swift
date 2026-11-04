import BlotDomain
import Foundation

public struct WorkspaceChatService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func createConversation(commandID: UUID, title: String, agentID: UUID? = nil, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let type = "conversation.create"; let workspaceID: UUID; let title: String; let agentID: UUID? }
        let input = try WorkspaceCoding.encode(Input(workspaceID: identity.workspaceID, title: title, agentID: agentID))
        return try await repository.execute(commandID: commandID, command: input, identity: identity, legacyResultID: commandID) { tx in
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceStorageError.invalidRecord }
            if let agentID { _ = try tx.require(BlotV3.AgentProfile.self, id: agentID) }
            let conversation = try BlotV3.Conversation(metadata: tx.metadata(id: commandID, now: now), agentId: agentID,
                title: title, mobileOwned: false, pinned: false, archived: false, kind: .direct)
            try tx.put(conversation, expectedVersion: 0)
            return commandID
        }
    }

    public func sendMessage(commandID: UUID, conversationID: UUID, content: String, replyToMessageID: UUID? = nil,
                            mentions: [BlotV3.MessageMention] = [], artifactIDs: [UUID] = [], now: Date = Date()) async throws -> UUID {
        struct Input: Encodable {
            let type = "conversation.send_message"
            let workspaceID: UUID; let conversationID: UUID; let content: String
            let replyToMessageID: UUID?; let mentions: [BlotV3.MessageMention]; let artifactIDs: [UUID]?
        }
        let input = try WorkspaceCoding.encode(Input(workspaceID: identity.workspaceID, conversationID: conversationID,
            content: content, replyToMessageID: replyToMessageID, mentions: mentions, artifactIDs: artifactIDs.isEmpty ? nil : artifactIDs))
        return try await repository.execute(commandID: commandID, command: input, identity: identity, legacyResultID: commandID) { tx in
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !artifactIDs.isEmpty else { throw WorkspaceStorageError.invalidRecord }
            guard content.utf8.count <= 128 * 1024, mentions.count <= 100, artifactIDs.count <= 8 else { throw WorkspaceStorageError.invalidParameters }
            guard let chat = try tx.record(BlotV3.Conversation.self, id: conversationID) else { throw WorkspaceStorageError.missingConversation }
            if let replyToMessageID {
                let source = try tx.require(BlotV3.Message.self, id: replyToMessageID)
                guard source.conversationId == conversationID else { throw WorkspaceStorageError.invalidRecord }
            }
            let participants = try tx.records(BlotV3.ConversationParticipant.self)
            for mention in mentions {
                guard mention.lengthUTF16 > 0, mention.startUTF16 <= content.utf16.count,
                      mention.lengthUTF16 <= content.utf16.count - mention.startUTF16,
                      Range(NSRange(location: mention.startUTF16, length: mention.lengthUTF16), in: content) != nil else {
                    throw WorkspaceStorageError.invalidRecord
                }
                _ = try tx.require(BlotV3.AgentProfile.self, id: mention.agentId)
                if chat.kind == .group {
                    guard participants.contains(where: { $0.conversationId == conversationID && $0.participantId == mention.agentId && $0.kind == .agent && !$0.removed }) else {
                        throw WorkspaceStorageError.permissionDenied
                    }
                } else if chat.agentId != mention.agentId { throw WorkspaceStorageError.permissionDenied }
            }
            guard Set(artifactIDs).count == artifactIDs.count else { throw WorkspaceStorageError.invalidParameters }
            for id in artifactIDs { _ = try tx.require(BlotV3.Artifact.self, id: id) }
            let position = try tx.nextMessagePosition(in: conversationID)
            let message = try BlotV3.Message(metadata: tx.metadata(id: commandID, now: now), conversationId: conversationID,
                role: .user, content: content, delivery: .saved, commandId: commandID, artifactIds: artifactIDs,
                replyToMessageId: replyToMessageID, mentions: mentions, position: position)
            try tx.put(message, expectedVersion: 0)
            return commandID
        }
    }
}
