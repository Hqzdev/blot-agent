import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneGroupMessageAuthor: View {
    let message: BlotV3.Message
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        let identity = PhoneConversationIdentity(conversation: store.currentConversation,
            agents: store.chatContent.agents, participants: store.chatContent.participants)
        let author = identity.author(of: message)
        Text(author?.name ?? identity.title).font(.caption.weight(.medium))
            .foregroundStyle(author.map { WorkspaceAvatarView.color($0.avatarColor).opacity(0.8) } ?? WorkspaceStyle.secondary)
            .padding(.leading, 12).padding(.top, 8).padding(.bottom, 3)
            .accessibilityElement(children: .ignore).accessibilityLabel(author?.name ?? identity.title)
            .accessibilityIdentifier("workspace.chat.message.author.\(message.metadata.id)")
    }
}
