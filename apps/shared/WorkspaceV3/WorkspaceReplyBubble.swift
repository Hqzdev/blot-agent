import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceReplyBubble: View {
    let draft: WorkspaceChatActivity.Draft
    var compact = false
    @Environment(WorkspaceStore.self) private var store

    private var agents: [BlotV3.AgentProfile] {
        guard store.currentConversation?.kind == .group else { return [] }
        return draft.agentIDs.compactMap { id in store.chatContent.agents.first { $0.metadata.id == id } }
    }

    var body: some View {
        HStack(spacing: 10) {
            if !agents.isEmpty {
                HStack(spacing: -7) {
                    ForEach(Array(agents.enumerated()), id: \.element.metadata.id) { index, agent in
                        WorkspaceAvatarView(agent: agent, size: compact ? 22 : 24)
                            .zIndex(Double(agents.count - index))
                            .transition(.opacity)
                    }
                }.accessibilityHidden(true)
            }
            WorkspaceTypingIndicator(size: compact ? 6 : 8)
            Spacer(minLength: compact ? 54 : 44)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(agents.isEmpty ? store.t("Agent is thinking") : agents.map(\.name).joined(separator: ", ") + ": " + store.t("Typing"))
        .id("thinking-" + draft.messageID.uuidString)
    }
}
