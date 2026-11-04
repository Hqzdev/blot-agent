import BlotDomain
import Foundation

/// One logical direct conversation per agent. Legacy thread IDs remain readable for offline replicas.
public struct WorkspaceDirectConversations: Sendable {
    private let aliases: [UUID: UUID]
    public let conversations: [BlotV3.Conversation]

    public init(_ conversations: [BlotV3.Conversation]) {
        let direct = conversations.filter { $0.kind != .group }
        let families = Dictionary(grouping: direct, by: \.agentId)
        var aliases: [UUID: UUID] = [:]
        for family in families.values {
            let first = family.min {
                $0.metadata.createdAt == $1.metadata.createdAt
                    ? $0.metadata.id.uuidString < $1.metadata.id.uuidString : $0.metadata.createdAt < $1.metadata.createdAt
            }!
            for chat in family { aliases[chat.metadata.id] = first.metadata.id }
        }
        self.aliases = aliases
        self.conversations = conversations.filter { aliases[$0.metadata.id] == nil || aliases[$0.metadata.id] == $0.metadata.id }
    }

    public func canonicalID(_ id: UUID) -> UUID { aliases[id] ?? id }

    public func messages(_ messages: [BlotV3.Message]) throws -> [BlotV3.Message] {
        let families = Dictionary(grouping: messages, by: { canonicalID($0.conversationId) })
        return try families.flatMap { id, family in
            let streams = Dictionary(grouping: family, by: \.conversationId).values.map(WorkspaceMessageOrder.ordered)
            guard streams.count > 1 || family.contains(where: { $0.conversationId != id }) else { return family }
            var offsets = Array(repeating: 0, count: streams.count)
            var merged: [BlotV3.Message] = []
            // Merge the heads chronologically, preserving each original thread's causal order.
            while let next = streams.indices.filter({ offsets[$0] < streams[$0].count }).min(by: {
                let a = streams[$0][offsets[$0]], b = streams[$1][offsets[$1]]
                return a.metadata.createdAt == b.metadata.createdAt
                    ? a.metadata.id.uuidString < b.metadata.id.uuidString : a.metadata.createdAt < b.metadata.createdAt
            }) {
                let old = streams[next][offsets[next]]
                offsets[next] += 1
                merged.append(try BlotV3.Message(metadata: old.metadata, conversationId: id, role: old.role,
                    content: old.content, delivery: old.delivery, commandId: old.commandId, artifactIds: old.artifactIds,
                    authorAgentId: old.authorAgentId, replyToMessageId: old.replyToMessageId, mentions: old.mentions,
                    position: merged.count + 1, executorDeviceId: old.executorDeviceId))
            }
            return merged
        }
    }

    func project(_ projection: WorkspaceProjection) throws -> WorkspaceProjection {
        guard aliases.contains(where: { $0.key != $0.value }) else { return projection }
        var result = projection
        result.conversations = try conversations.map { chat in
            let family = projection.conversations.filter { canonicalID($0.metadata.id) == chat.metadata.id }
            return try BlotV3.Conversation(metadata: chat.metadata, agentId: chat.agentId, title: chat.title,
                mobileOwned: chat.mobileOwned, pinned: family.contains(where: \.pinned),
                archived: family.allSatisfy(\.archived), kind: chat.kind)
        }
        result.messages = try messages(projection.messages)
        result.messages.sort {
            $0.metadata.createdAt == $1.metadata.createdAt ? $0.metadata.id.uuidString < $1.metadata.id.uuidString
                : $0.metadata.createdAt < $1.metadata.createdAt
        }
        let positions = Dictionary(uniqueKeysWithValues: Dictionary(grouping: result.messages, by: \.conversationId).values.flatMap {
            WorkspaceMessageOrder.ordered($0).enumerated().map { ($0.element.metadata.id, $0.element.position ?? $0.offset + 1) }
        })
        result.readPositions = try projection.readPositions.map { old in
            try BlotV3.ConversationReadPosition(metadata: old.metadata, conversationId: canonicalID(old.conversationId),
                participantId: old.participantId, messageId: old.messageId, position: positions[old.messageId] ?? old.position)
        }
        result.readPositions = Dictionary(grouping: result.readPositions, by: { "\($0.conversationId):\($0.participantId)" })
            .values.compactMap { $0.max(by: { $0.position < $1.position }) }
        result.summaries = try projection.summaries.map { old in
            try BlotV3.ContextSummary(metadata: old.metadata, conversationId: canonicalID(old.conversationId),
                content: old.content, sourceIds: old.sourceIds, valid: old.valid)
        }
        return result
    }
}
