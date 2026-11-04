import BlotDesign
import BlotDomain
import SwiftUI

struct MacWorkspaceSidebar: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var isCreating: Bool { [.createAgent, .editAgent, .firstAgent].contains(store.route) }
    @State private var showsArchive = false

    private var chats: [BlotV3.Conversation] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let order = store.desktopContent.sidebarOrder(in: store.selectedConversationID)
        return store.snapshot.conversations.filter { chat in
            guard chat.archived == showsArchive else { return false }
            let text = store.t(chat.title) + " " + preview(for: chat)
            return search.isEmpty || text.localizedStandardContains(search)
        }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.pinned && $1.pinned {
                let left = store.chatInteractions.pinnedOrder.firstIndex(of: $0.metadata.id) ?? Int.max
                let right = store.chatInteractions.pinnedOrder.firstIndex(of: $1.metadata.id) ?? Int.max
                if left != right { return left < right }
            }
            if $0.metadata.updatedAt != $1.metadata.updatedAt { return $0.metadata.updatedAt > $1.metadata.updatedAt }
            return (order.firstIndex(of: $0.metadata.id) ?? Int.max) < (order.firstIndex(of: $1.metadata.id) ?? Int.max)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if store.mode == .live && !store.snapshot.agents.isEmpty {
                    Button { store.groupCreationVisible = true } label: { BlotIcon(symbol: "person.2").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help(store.t("New group")).accessibilityLabel(store.t("New group"))
                }
                if !store.snapshot.agents.isEmpty {
                    Button { store.navigate(.home) } label: { BlotIcon(.plus, size: 15).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help(store.t("New chat")).accessibilityLabel(store.t("New chat"))
                }
            }.padding(.horizontal, 10).frame(height: 44)
            if !store.snapshot.agents.isEmpty { searchField.padding(.horizontal, 12).padding(.bottom, 8) }
            if isCreating { creationRow.padding(.horizontal, 12).padding(.top, 5) }
            if store.snapshot.conversations.isEmpty && isCreating {
                Spacer()
                Text(store.t("No chats yet")).font(.system(size: 14)).foregroundStyle(WorkspaceStyle.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if !showsArchive && query.isEmpty && !store.pinnedConversations.isEmpty { pinnedStrip }
                        if showsArchive || store.snapshot.conversations.contains(where: \.archived) {
                            Button { showsArchive.toggle() } label: {
                                HStack(spacing: 8) {
                                    BlotIcon(showsArchive ? .chevronLeft : .archiveBox, size: 15)
                                    Text(store.t(showsArchive ? "Chats" : "Archive"))
                                    Spacer()
                                    if !showsArchive {
                                        WorkspaceUnreadBadge(count: store.snapshot.conversations.filter(\.archived).reduce(0) {
                                            $0 + store.chatInteractions.unreadCount(in: $1.metadata.id)
                                        }, size: 18)
                                    }
                                }.padding(.horizontal, 9).frame(height: 34).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        ForEach(chats, id: \.metadata.id) { chat in chatRow(chat) }
                        if chats.isEmpty {
                            Text(store.t(query.isEmpty ? (showsArchive ? "Archive is empty" : "Start a conversation") : "No results"))
                                .font(MacWorkspaceStyle.caption).foregroundStyle(WorkspaceStyle.secondary).padding(20)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 12)
                }.scrollIndicators(.hidden)
            }
            footer
        }.font(MacWorkspaceStyle.body).background(MacWorkspaceStyle.sidebar)
    }

    private var creationRow: some View {
        HStack(spacing: 10) {
            WorkspaceAvatar(shape: .init(rawValue: store.form.agent.shape) ?? .round,
                color: WorkspaceAvatarView.color(store.form.agent.color), size: 40)
            Text(store.snapshot.agents.isEmpty ? store.t("Create your first agent") : store.form.agent.name.isEmpty ? store.t("New agent") : store.form.agent.name)
                .font(.system(size: 14, weight: .medium)).lineLimit(2)
            Spacer(minLength: 0)
        }.padding(10).background(BlotColor.selected, in: RoundedRectangle(cornerRadius: BlotRadius.panel))
            .accessibilityAddTraits(.isSelected)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            BlotIcon(.search, size: 12).foregroundStyle(WorkspaceStyle.secondary)
            TextField(store.t("Search"), text: $query).textFieldStyle(.plain).focused($searchFocused)
                .accessibilityLabel(store.t("Search chats"))
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: { BlotIcon(.closeCircle, size: 12) }
                    .buttonStyle(.plain).accessibilityLabel(store.t("Clear search"))
            }
        }.font(.system(size: 12)).padding(.horizontal, 9).frame(height: 28)
            .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: BlotRadius.control))
    }

    private func preview(for chat: BlotV3.Conversation) -> String {
        if let message = store.snapshot.messages.last(where: { $0.conversationId == chat.metadata.id }) { return store.t(message.content) }
        return store.snapshot.agents.first { $0.metadata.id == chat.agentId }.map { store.t($0.instructions) } ?? ""
    }

    private var pinnedStrip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.pinnedConversations, id: \.metadata.id) { chat in
                    Button { store.openConversation(chat.metadata.id) } label: {
                        VStack(spacing: 5) {
                            chatAvatar(chat, size: 46)
                                .overlay(alignment: .topTrailing) {
                                    WorkspaceUnreadBadge(count: store.chatInteractions.unreadCount(in: chat.metadata.id),
                                        muted: store.chatInteractions.isMuted(chat.metadata.id), size: 16)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    BlotIcon(.star, size: 8).foregroundStyle(.white).frame(width: 16, height: 16)
                                        .background(.orange, in: Circle()).overlay(Circle().strokeBorder(WorkspaceStyle.canvas, lineWidth: 1.5))
                                }
                            Text(store.t(chat.title)).font(.system(size: 10)).lineLimit(1).frame(width: 68)
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain).contextMenu { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
                }
            }.padding(.horizontal, 8)
        }.scrollIndicators(.hidden)
    }

    private func chatAvatar(_ chat: BlotV3.Conversation, size: CGFloat) -> some View {
        Group {
            if let agent = store.snapshot.agents.first(where: { $0.metadata.id == chat.agentId }) { WorkspaceAvatarView(agent: agent, size: size) }
            else { WorkspaceAvatar(size: size) }
        }.overlay(alignment: .bottomLeading) {
            WorkspacePresenceDot(online: store.isAgentOnline(chat.agentId, in: chat.metadata.id), size: 13)
        }
    }

    private func chatRow(_ chat: BlotV3.Conversation) -> some View {
        Button { store.openConversation(chat.metadata.id) } label: {
            HStack(spacing: 9) {
                chatAvatar(chat, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(store.t(chat.title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if chat.pinned { BlotIcon(.star, size: 9).foregroundStyle(.orange) }
                        Spacer(minLength: 0)
                        Text(chat.metadata.updatedAt, format: .dateTime.hour().minute())
                            .font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary).fixedSize()
                    }
                    HStack(spacing: 5) {
                        if store.chatActivity.isTyping(in: chat.metadata.id) { WorkspaceTypingPreview().font(.system(size: 12)) }
                        else {
                            Text(preview(for: chat)).font(.system(size: 12))
                                .foregroundStyle(store.desktopContent.status(in: chat.metadata.id) == .needsApproval ? Color.orange : WorkspaceStyle.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if store.chatInteractions.isMuted(chat.metadata.id) { BlotIcon(.bellOff, size: 11).foregroundStyle(WorkspaceStyle.secondary) }
                        if store.desktopContent.status(in: chat.metadata.id) == .needsApproval {
                            Circle().fill(.orange).frame(width: 6, height: 6).accessibilityLabel(store.t("Waiting for approval"))
                        }
                        WorkspaceUnreadBadge(count: store.chatInteractions.unreadCount(in: chat.metadata.id),
                            muted: store.chatInteractions.isMuted(chat.metadata.id), size: 18)
                    }
                }
            }.padding(.horizontal, 7).frame(height: 60)
                .background(store.route == .chat && store.selectedConversationID == chat.metadata.id ? BlotColor.selected : .clear,
                            in: RoundedRectangle(cornerRadius: BlotRadius.control))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(chat.title)
            .contextMenu { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
    }

    private var footer: some View {
        VStack(spacing: 3) {
            if !store.snapshot.agents.isEmpty {
                HStack {
                    footerButton("Plugins", glyph: .puzzle, route: .connections)
                    Menu {
                        BlotIconButton(store.t("Agents"), symbol: "person.2") { store.navigate(.agents) }
                        BlotIconButton(store.t("Create agent"), symbol: "plus") { store.navigate(.createAgent) }
                        BlotIconButton(store.t("Automations"), symbol: "calendar") { store.navigate(.schedules) }
                        BlotIconButton(store.t("Files"), symbol: "folder") { store.navigate(.files) }
                        BlotIconButton(store.t("Computers"), symbol: "desktopcomputer") { store.navigate(.devices) }
                        if store.currentConversation != nil {
                            BlotIconButton(store.t("Task details"), symbol: "list.bullet") { store.navigate(.running) }
                        }
                    } label: { BlotIcon(.more, size: 16).frame(width: 26, height: 26) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(store.t("More"))
                }
            }
            HStack {
                footerButton(store.form.account.name.isEmpty ? "Account" : store.form.account.name, glyph: .person, route: .account)
                Button { store.navigate(.settings) } label: { BlotIcon(.settings, size: 15).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).help(store.t("Settings")).accessibilityLabel(store.t("Settings"))
            }
        }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
    }

    private func footerButton(_ title: String, glyph: BlotGlyph, route: WorkspaceRoute) -> some View {
        Button { store.navigate(route) } label: {
            HStack(spacing: 10) { BlotIcon(glyph, size: 17).frame(width: 22); Text(store.t(title)); Spacer(minLength: 0) }
                .frame(height: 34).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
