import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceReplyBubble: View {
    let draft: WorkspaceChatActivity.Draft
    var compact = false
    var showsAvatar = true
    @Environment(WorkspaceStore.self) private var store

    private var agents: [BlotV3.AgentProfile] {
        let active = draft.agentIDs.compactMap { id in store.chatContent.agents.first { $0.metadata.id == id } }
        if !active.isEmpty { return active }
        if let agent = store.chatContent.agents.first(where: { $0.metadata.id == store.currentConversation?.agentId }) { return [agent] }
        return []
    }

    private var usesAvatarColumn: Bool {
        #if os(macOS)
        store.currentConversation?.kind == .group
        #else
        true
        #endif
    }

    private var working: Bool { [.planning, .queued, .running].contains(store.currentTask?.state) }
    private var status: String {
        #if os(macOS)
        store.language == "ru" ? "Думаю" : "Thinking"
        #else
        store.t(working ? "Working" : "Typing")
        #endif
    }

    var body: some View {
        HStack(spacing: 10) {
            if usesAvatarColumn && showsAvatar && !agents.isEmpty {
                HStack(spacing: -7) {
                    ForEach(Array(agents.enumerated()), id: \.element.metadata.id) { index, agent in
                        WorkspaceThinkingAvatar(agent: agent, size: compact ? 24 : 26, state: working ? .working : .thinking)
                            .zIndex(Double(agents.count - index))
                            .transition(.opacity)
                    }
                }.accessibilityHidden(true)
            } else if usesAvatarColumn && !showsAvatar { Color.clear.frame(width: compact ? 24 : 26, height: compact ? 24 : 26) }
            #if os(macOS)
            MacChatActivityLabel(title: status).font(compact ? .system(size: 13) : .callout)
            #else
            Text(status + "…").font(compact ? .system(size: 13) : .callout)
                .foregroundStyle(WorkspaceStyle.secondary)
            #endif
            Spacer(minLength: compact ? 54 : 44)
        }
        .padding(.vertical, 8)
        .kAnimation(KMotion.standard, value: draft.agentIDs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(agents.isEmpty ? store.t("Agent is thinking") : agents.map(\.name).joined(separator: ", ") + ": " + status)
        .id("thinking-" + draft.messageID.uuidString)
    }
}
