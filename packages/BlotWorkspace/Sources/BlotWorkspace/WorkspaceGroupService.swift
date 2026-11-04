import BlotDomain
import Foundation

public struct WorkspaceGroupService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func create(commandID: UUID, title: String, agentIDs: [UUID], now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let title: String; let agentIDs: [UUID] }
        let command = try WorkspaceCommand(type: "group.create", workspaceID: identity.workspaceID,
            payload: Input(title: title, agentIDs: agentIDs)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !agentIDs.isEmpty, Set(agentIDs).count == agentIDs.count else { throw WorkspaceStorageError.invalidParameters }
            for id in agentIDs { _ = try tx.require(BlotV3.AgentProfile.self, id: id) }
            let chat = try BlotV3.Conversation(metadata: tx.metadata(id: commandID, now: now), agentId: agentIDs.first,
                title: title, mobileOwned: false, pinned: false, archived: false, kind: .group)
            try tx.put(chat, expectedVersion: 0)
            try Self.member(tx, conversationID: commandID, participantID: tx.identity.ownerID, kind: .user, removed: false, now: now)
            for id in agentIDs { try Self.member(tx, conversationID: commandID, participantID: id, kind: .agent, removed: false, now: now) }
            return commandID
        }
    }

    public func setAgent(commandID: UUID, conversationID: UUID, agentID: UUID, removed: Bool, now: Date = Date()) async throws {
        struct Input: Encodable { let conversationID: UUID; let agentID: UUID; let removed: Bool }
        let command = try WorkspaceCommand(type: "group.participant.set", workspaceID: identity.workspaceID,
            payload: Input(conversationID: conversationID, agentID: agentID, removed: removed)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let chat = try tx.require(BlotV3.Conversation.self, id: conversationID)
            guard chat.kind == .group else { throw WorkspaceStorageError.invalidParameters }
            _ = try tx.require(BlotV3.AgentProfile.self, id: agentID)
            try Self.member(tx, conversationID: conversationID, participantID: agentID, kind: .agent, removed: removed, now: now)
            return conversationID
        }
    }

    private static func member(_ tx: WorkspaceTransaction, conversationID: UUID, participantID: UUID,
                               kind: BlotV3.ParticipantKind, removed: Bool, now: Date) throws {
        let id = WorkspaceLogicalID.make(kind: "ConversationParticipant", workspaceID: tx.identity.workspaceID,
            parts: [conversationID.uuidString, participantID.uuidString, kind.rawValue])
        let old = try tx.record(BlotV3.ConversationParticipant.self, id: id)
        guard old?.removed != removed else { return }
        let record = try BlotV3.ConversationParticipant(metadata: tx.metadata(id: id, now: now, replacing: old?.metadata),
            conversationId: conversationID, participantId: participantID, kind: kind, removed: removed)
        try tx.put(record, expectedVersion: old?.metadata.version ?? 0)
    }
}
