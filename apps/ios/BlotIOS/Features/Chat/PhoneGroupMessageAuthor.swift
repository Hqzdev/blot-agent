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
        HStack(spacing: 7) {
            if let author { WorkspaceAvatarView(agent: author, size: 22) }
            else { BlotIcon(.people, size: 22) }
            Text(author?.name ?? identity.title).font(.caption.weight(.medium)).foregroundStyle(WorkspaceStyle.secondary)
        }.padding(.leading, 12).padding(.bottom, 3)
            .accessibilityElement(children: .ignore).accessibilityLabel(author?.name ?? identity.title)
            .accessibilityIdentifier("workspace.chat.message.author.\(message.metadata.id)")
    }
}
