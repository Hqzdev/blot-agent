import BlotDesign
import BlotDomain
import SwiftUI

struct MacMessageBubble: View {
    let message: BlotV3.Message
    let showMessage: (UUID) -> Void
    @Environment(WorkspaceStore.self) private var store
    private var isUser: Bool { message.role == .user }
    private var metadata: WorkspaceMessageMetadata? { store.chatInteractions.messages[message.metadata.id] }
    private var quoted: BlotV3.Message? {
        (metadata?.replyToMessageID ?? message.replyToMessageId).flatMap { id in store.message(id) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 54) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if let quoted {
                    Button { showMessage(quoted.metadata.id) } label: { WorkspaceQuotedMessage(message: quoted) }
                        .buttonStyle(.plain).padding(.horizontal, 12)
                }
                WorkspaceMessageText(text: store.mode == .live ? message.content : store.t(message.content), markdown: !isUser,
                    agents: store.chatContent.agents, skills: store.chatContent.skills)
                    .font(.system(size: 14)).lineSpacing(3)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .foregroundStyle(isUser ? BlotColor.onInverse : WorkspaceStyle.ink)
                    .background(isUser ? BlotColor.inverse : WorkspaceStyle.surface,
                                in: RoundedRectangle(cornerRadius: BlotRadius.panel))
                    .contextMenu { WorkspaceMessageActionsMenu(message: message).environment(store) }
                WorkspaceMessagePlugins(message: message).padding(.horizontal, 12)
                if let reaction = metadata?.reaction {
                    Button { store.toggleReaction(reaction, to: message.metadata.id) } label: {
                        Text(reaction).font(.system(size: 16)).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(WorkspaceStyle.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(MacWorkspaceStyle.edge))
                    }.buttonStyle(.plain).accessibilityLabel(store.t("Remove reaction") + " " + reaction)
                }
                if store.mode == .live {
                    Text(store.deliveryTitle(message.delivery)).font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, 8)
                } else if isUser {
                    let read = message.delivery == .completed || store.chatActivity.readMessageIDs.contains(message.metadata.id)
                        || store.chatInteractions.agentReadMessageIDs?.contains(message.metadata.id) == true
                    Text(store.t(read ? "Read" : "Sent")).font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, 8)
                }
            }.frame(maxWidth: 420, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 54) }
        }.padding(.top, isUser ? 12 : 0)
    }
}
