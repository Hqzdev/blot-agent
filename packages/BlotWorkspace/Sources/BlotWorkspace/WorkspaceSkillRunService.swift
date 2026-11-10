import BlotDomain
import Foundation

/// Expands a revision once and atomically enqueues its immutable task input.
public struct WorkspaceSkillRunService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }
    public func run(commandID: UUID, skillID: UUID, revisionID: UUID? = nil, agentID: UUID,
                    values: [String: String], conversationID: UUID? = nil, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable {
            let skillID: UUID; let revisionID: UUID?; let agentID: UUID; let values: [String: String]; let conversationID: UUID?
        }
        let command = try WorkspaceCommand(type: "skill.run", workspaceID: identity.workspaceID,
            payload: Input(skillID: skillID, revisionID: revisionID, agentID: agentID, values: values, conversationID: conversationID)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let skill = try tx.require(BlotV3.Skill.self, id: skillID)
            let revision = try tx.require(BlotV3.SkillRevision.self, id: revisionID ?? skill.activeRevisionId)
            guard revision.skillId == skillID else { throw WorkspaceSkillError.revisionUnavailable }
            try WorkspaceSkillAccess.require(revisionID: revision.metadata.id, agentID: agentID, tx: tx)
            let goal = try WorkspaceSkillService.render(revision, values: values)
            let chatID: UUID
            if let conversationID {
                let chat = try tx.require(BlotV3.Conversation.self, id: conversationID)
                let member = try tx.records(BlotV3.ConversationParticipant.self).contains(where: {
                    $0.conversationId == conversationID && $0.kind == .agent && $0.participantId == agentID && !$0.removed
                })
                guard !chat.archived, chat.kind == .group ? member : chat.agentId == agentID else { throw WorkspaceSkillError.wrongConversation }
                chatID = conversationID
            } else if let chat = try tx.records(BlotV3.Conversation.self).first(where: { $0.agentId == agentID && $0.kind != .group && !$0.archived }) {
                chatID = chat.metadata.id
            } else {
                chatID = WorkspaceLogicalID.make(kind: "SkillConversation", workspaceID: identity.workspaceID, parts: [commandID.uuidString])
                let agent = try tx.require(BlotV3.AgentProfile.self, id: agentID)
                try tx.put(BlotV3.Conversation(metadata: tx.metadata(id: chatID, now: now), agentId: agentID,
                    title: agent.name, mobileOwned: false, pinned: false, archived: false, kind: .direct), expectedVersion: 0)
            }
            return try WorkspaceTaskService.insert(tx, taskID: commandID, conversationID: chatID, agentID: agentID, goal: goal,
                executorDeviceID: identity.deviceID, parentTaskID: nil, skillRevisionID: revision.metadata.id, budgetTokenLimit: 20_000, now: now)
        }
    }
}
