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
            if search.isEmpty { return !chat.pinned || showsArchive }
            let text = store.t(chat.title) + " " + preview(for: chat)
            return text.localizedStandardContains(search)
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
        let showsPins = !showsArchive && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let pinnedChats = showsPins ? store.pinnedConversations : []
        let chats = chats
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
                if !pinnedChats.isEmpty { MacPinnedChats(chats: pinnedChats).padding(.bottom, 6) }
                ScrollView {
                    LazyVStack(spacing: 2) {
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
                            }.buttonStyle(.plain).macSidebarHoverTarget()
                        }
                        ForEach(chats, id: \.metadata.id) { chat in chatRow(chat) }
                        if chats.isEmpty && pinnedChats.isEmpty {
                            Text(store.t(query.isEmpty ? (showsArchive ? "Archive is empty" : "Start a conversation") : "No results"))
                                .font(MacWorkspaceStyle.caption).foregroundStyle(WorkspaceStyle.secondary).padding(20)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 12)
                }.scrollIndicators(.hidden).macSidebarHoverSection(radius: BlotRadius.control)
            }
            footer.macSidebarHoverSection(radius: BlotRadius.control)
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
        }.buttonStyle(BlotPlainButtonStyle(showsHover: false)).macSidebarHoverTarget().help(chat.title)
            .macCommandMenu { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
    }

    private var footer: some View {
        VStack(spacing: 3) {
            if !store.snapshot.agents.isEmpty {
                HStack {
                    footerButton("Plugins", glyph: .puzzle, route: .connections)
                    WorkspaceMenu {
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
                    .buttonStyle(.plain).macSidebarHoverTarget().help(store.t("Settings")).accessibilityLabel(store.t("Settings"))
            }
        }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
    }

    private func footerButton(_ title: String, glyph: BlotGlyph, route: WorkspaceRoute) -> some View {
        Button { store.navigate(route) } label: {
            HStack(spacing: 10) { BlotIcon(glyph, size: 17).frame(width: 22); Text(store.t(title)); Spacer(minLength: 0) }
                .frame(height: 34).contentShape(Rectangle())
        }.buttonStyle(.plain).macSidebarHoverTarget()
    }
}

struct MacPinnedChats: View {
    let chats: [BlotV3.Conversation]
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 6) {
                ForEach(chats, id: \.metadata.id) { chat in
                    let id = chat.metadata.id
                    let title = store.t(chat.title)
                    let selected = store.route == .chat && store.selectedConversationID == id
                    Button { store.openConversation(id) } label: {
                        VStack(spacing: 6) {
                            avatar(for: chat)
                                .overlay(alignment: .topTrailing) {
                                    WorkspaceUnreadBadge(count: store.chatInteractions.unreadCount(in: id),
                                        muted: store.chatInteractions.isMuted(id), size: 16)
                                }
                            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(width: 78).padding(.vertical, 6)
                        .background(selected ? BlotColor.selected : .clear, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BlotPlainButtonStyle(showsHover: false)).macSidebarHoverTarget().macHoverTip(title)
                    .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
                    .macCommandMenu { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
                }
            }.padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden).macSidebarHoverSection(radius: 14)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("workspace.chat.pinned-conversations")
    }

    @ViewBuilder private func avatar(for chat: BlotV3.Conversation) -> some View {
        if chat.kind == .group {
            let memberIDs = Set(store.chatContent.participants.filter {
                $0.conversationId == chat.metadata.id && !$0.removed
            }.map(\.participantId))
            MacLiveTeamGroupAvatar(agents: store.chatContent.agents.filter { memberIDs.contains($0.metadata.id) }, size: 46)
        } else {
            Group {
                if let agent = store.chatContent.agents.first(where: { $0.metadata.id == chat.agentId }) {
                    WorkspaceAvatarView(agent: agent, size: 46)
                } else {
                    WorkspaceAvatar(size: 46)
                }
            }.overlay(alignment: .bottomLeading) {
                WorkspacePresenceDot(online: store.isAgentOnline(chat.agentId, in: chat.metadata.id), size: 13)
            }
        }
    }
}
