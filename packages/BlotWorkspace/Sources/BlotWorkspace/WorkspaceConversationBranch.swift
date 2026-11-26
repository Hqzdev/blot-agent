import BlotDomain
import Foundation

/// Copies settled dialogue only. Tool execution, approvals and credentials never move to the branch.
public struct WorkspaceConversationBranch: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func create(commandID: UUID, messageID: UUID, agentID: UUID, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let source: UUID; let agent: UUID }
        let command = try WorkspaceCommand(type: "conversation.branch", workspaceID: identity.workspaceID,
            payload: Input(source: messageID, agent: agentID)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let target = try tx.require(BlotV3.Message.self, id: messageID)
            guard target.role == .assistant, target.delivery == .completed else { throw WorkspaceStorageError.invalidParameters }
            let agent = try tx.require(BlotV3.AgentProfile.self, id: agentID)
            let chats = try tx.records(BlotV3.Conversation.self)
            let index = WorkspaceDirectConversations(chats)
            let sourceID = index.canonicalID(target.conversationId)
            let source = try index.messages(tx.records(BlotV3.Message.self)).filter { $0.conversationId == sourceID }
            let ordered = WorkspaceMessageOrder.ordered(source)
            guard let end = ordered.firstIndex(where: { $0.metadata.id == messageID }) else { throw WorkspaceStorageError.missingRecord }
            let prefix = ordered[...end].filter { $0.role == .user || $0.role == .assistant && $0.delivery == .completed }
            let chat = try BlotV3.Conversation(metadata: tx.metadata(id: commandID, now: now), agentId: agentID,
                title: agent.name + " · Branch", mobileOwned: false, pinned: false, archived: false, kind: .group,
                parentConversationId: sourceID, parentMessageId: messageID)
            try tx.put(chat, expectedVersion: 0)
            // An isolated one-agent container also stays separate in older clients,
            // which canonicalize every DIRECT conversation for the same agent.
            try WorkspaceGroupService.member(tx, conversationID: commandID, participantID: identity.ownerID, kind: .user, removed: false, now: now)
            try WorkspaceGroupService.member(tx, conversationID: commandID, participantID: agentID, kind: .agent, removed: false, now: now)
            let ids = Dictionary(uniqueKeysWithValues: prefix.map { ($0.metadata.id, WorkspaceLogicalID.make(kind: "BranchMessage",
                workspaceID: identity.workspaceID, parts: [commandID.uuidString, $0.metadata.id.uuidString])) })
            for (position, message) in prefix.enumerated() {
                let command = WorkspaceLogicalID.make(kind: "BranchCommand", workspaceID: identity.workspaceID,
                    parts: [commandID.uuidString, message.commandId.uuidString])
                let copied = try BlotV3.Message(metadata: tx.metadata(id: ids[message.metadata.id]!, now: now), conversationId: commandID,
                    role: message.role, content: message.content, delivery: .completed, commandId: command, artifactIds: message.artifactIds,
                    authorAgentId: message.authorAgentId, replyToMessageId: message.replyToMessageId.flatMap { ids[$0] },
                    position: position + 1)
                try tx.put(copied, expectedVersion: 0)
            }
            return commandID
        }
    }
}
