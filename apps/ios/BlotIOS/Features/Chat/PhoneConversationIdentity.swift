import BlotDomain
import Foundation

/// Group membership comes from participant records, independently of its coordinator and title.
struct PhoneConversationIdentity {
    let conversation: BlotV3.Conversation?
    let agents: [BlotV3.AgentProfile]
    let participants: [BlotV3.ConversationParticipant]

    var isGroup: Bool { conversation?.kind == .group }
    var agent: BlotV3.AgentProfile? { agents.first { $0.metadata.id == conversation?.agentId } }
    var title: String { isGroup ? conversation?.title ?? "" : agent?.name ?? "Blot Agent" }
    var members: [BlotV3.AgentProfile] {
        guard isGroup, let conversation else { return [] }
        let ids = Set(participants.filter {
            $0.conversationId == conversation.metadata.id && $0.kind == .agent && !$0.removed
        }.map(\.participantId))
        return agents.filter { ids.contains($0.metadata.id) }
    }
    func author(of message: BlotV3.Message) -> BlotV3.AgentProfile? {
        guard message.role == .assistant else { return nil }
        let id = message.authorAgentId ?? (isGroup ? nil : conversation?.agentId)
        return agents.first { $0.metadata.id == id }
    }
}
