import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceChatActionsMenu: View {
    let chat: BlotV3.Conversation
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        BlotIconButton(store.t("Rename chat"), symbol: "pencil") { store.beginChatRename(chat.metadata.id) }
        Divider()
        BlotIconButton(store.t(chat.pinned ? "Unpin chat" : "Pin chat"), symbol: "pin") {
            store.toggleChatPin(chat.metadata.id)
        }
        BlotIconButton(store.t(chat.archived ? "Unarchive chat" : "Archive chat"), symbol: "archivebox") {
            store.setChatArchived(chat.metadata.id, archived: !chat.archived)
        }
        BlotIconButton(store.t(store.chatInteractions.unreadCount(in: chat.metadata.id) > 0 ? "Mark as read" : "Mark as unread"), symbol: "envelope") {
            if store.chatInteractions.unreadCount(in: chat.metadata.id) > 0 { store.markChatRead(chat.metadata.id) }
            else { store.markChatUnread(chat.metadata.id) }
        }
        BlotIconButton(store.t(store.chatInteractions.isMuted(chat.metadata.id) ? "Unmute chat" : "Mute chat"),
                       symbol: store.chatInteractions.isMuted(chat.metadata.id) ? "bell" : "bell.slash") {
            store.toggleChatMute(chat.metadata.id)
        }
        if store.chatActivity.isResponding(in: chat.metadata.id) {
            BlotIconButton(store.t("Stop reply"), symbol: "stop") { store.stopReply(in: chat.metadata.id) }
        }
        if let agentID = chat.agentId {
            Divider()
            BlotIconButton(store.t("Agent"), symbol: "person.crop.circle") { store.selectAgent(agentID) }
            BlotIconButton(store.t("Edit agent"), symbol: "paintbrush") { store.editChatAgent(agentID) }
        }
        Divider()
        Button(role: .destructive) { store.pendingChatDeletionID = chat.metadata.id } label: {
            BlotLabel(store.t("Delete chat"), symbol: "trash")
        }
    }
}
