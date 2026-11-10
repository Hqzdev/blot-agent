import BlotDomain
import BlotDesign
import SwiftUI

struct PhoneConversationTitle: View {
    let identity: PhoneConversationIdentity
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        Button {
            if identity.isGroup, let id = identity.conversation?.metadata.id { store.editGroup(id) }
            else { store.agentPickerVisible = true }
        } label: {
            PhoneGlassCapsule {
                HStack(spacing: 8) {
                    if identity.isGroup { PhoneGroupAvatar(agents: identity.members, size: 30) }
                    else if let agent = identity.agent { WorkspaceAvatarView(agent: agent, size: 26) }
                    else { WorkspaceAvatar(size: 26) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(identity.title).font(.body.weight(.medium)).lineLimit(1)
                        if let id = store.selectedConversationID, store.chatActivity.isTyping(in: id) {
                            WorkspaceTypingPreview().font(.caption2)
                        } else if identity.isGroup {
                            Text(store.t("Group members") + " · " + identity.members.count.formatted())
                                .font(.caption2).foregroundStyle(WorkspaceStyle.secondary).lineLimit(1)
                        } else {
                            HStack(spacing: 4) {
                                WorkspacePresenceDot(online: online, size: 6)
                                Text(store.t(online ? "Online" : "Not online"))
                            }.font(.caption2).foregroundStyle(WorkspaceStyle.secondary)
                        }
                    }
                    BlotIcon(.chevronDown, size: 12)
                }
            }
        }.buttonStyle(.plain)
            .accessibilityLabel(identity.title)
            .accessibilityHint(store.t(identity.isGroup ? "Group members" : "Choose an agent"))
            .accessibilityIdentifier(identity.isGroup ? "workspace.chat.group.title" : "workspace.chat.agent.title")
    }
    private var online: Bool { store.isAgentOnline(identity.agent?.metadata.id, in: store.selectedConversationID) }
}
