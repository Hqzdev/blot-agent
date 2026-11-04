import BlotDomain
import Foundation

@MainActor
enum WorkspaceChatOperations {
    static func updating(_ chat: BlotV3.Conversation, pinned: Bool? = nil, archived: Bool? = nil, title: String? = nil) throws -> BlotV3.Conversation {
        try .init(metadata: chat.metadata, agentId: chat.agentId, title: title ?? chat.title, mobileOwned: chat.mobileOwned,
                  pinned: pinned ?? chat.pinned, archived: archived ?? chat.archived)
    }

    static func migratePins(in snapshot: WorkspaceSnapshot, agentIDs: Set<UUID>) throws -> WorkspaceSnapshot {
        var result = snapshot
        for agent in result.agents where agentIDs.contains(agent.metadata.id) {
            if let index = result.conversations.indices.filter({ result.conversations[$0].agentId == agent.metadata.id && !result.conversations[$0].archived })
                .max(by: { result.conversations[$0].metadata.updatedAt < result.conversations[$1].metadata.updatedAt }) {
                result.conversations[index] = try updating(result.conversations[index], pinned: true)
            } else if !result.conversations.contains(where: { $0.agentId == agent.metadata.id }) {
                let metadata = try BlotV3.RecordMetadata(id: UUID(), ownerId: agent.metadata.ownerId,
                    workspaceId: agent.metadata.workspaceId, version: 1, createdAt: Date(), updatedAt: Date())
                result.conversations.append(try .init(metadata: metadata, agentId: agent.metadata.id,
                    title: agent.name, mobileOwned: false, pinned: true, archived: false))
            }
        }
        return result
    }
}
