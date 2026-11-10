import BlotDomain
import Foundation

struct PhoneSearchResults {
    let agents: [BlotV3.AgentProfile]
    let groups: [BlotV3.Conversation]
    var isEmpty: Bool { agents.isEmpty && groups.isEmpty }

    init(snapshot: WorkspaceSnapshot, query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ text: String) -> Bool { query.isEmpty || text.localizedStandardContains(query) }
        agents = snapshot.agents.filter { matches($0.name) || matches($0.instructions) }
        groups = snapshot.conversations.filter { group in
            guard group.kind == .group else { return false }
            if matches(group.title) { return true }
            let identity = PhoneConversationIdentity(conversation: group, agents: snapshot.agents, participants: snapshot.participants ?? [])
            return identity.members.contains { matches($0.name) }
        }.sorted {
            if $0.metadata.updatedAt != $1.metadata.updatedAt { return $0.metadata.updatedAt > $1.metadata.updatedAt }
            return $0.metadata.id.uuidString < $1.metadata.id.uuidString
        }
    }
}
