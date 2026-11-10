import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneChatsView: View {
    private enum Row: Identifiable {
        enum ID: Hashable { case pinned, archive, agent(UUID), conversation(UUID), empty, feedback }
        case pinned, archive, agent(BlotV3.AgentProfile), conversation(BlotV3.Conversation), empty, feedback

        var id: ID {
            switch self {
            case .pinned: .pinned
            case .archive: .archive
            case .agent(let agent): .agent(agent.metadata.id)
            case .conversation(let chat): .conversation(chat.metadata.id)
            case .empty: .empty
            case .feedback: .feedback
            }
        }
    }
    private enum Creation { case agent, group }
    @State private var creationMenuVisible = false
    @State private var pendingCreation: Creation?
    var showsAgents = false
    var showsArchive = false
    @Environment(WorkspaceStore.self) private var store

    private var scrollRoute: WorkspaceRoute { showsArchive ? .archivedChats : showsAgents ? .agents : .chats }
    private var conversations: [BlotV3.Conversation] {
        store.snapshot.conversations.filter { showsArchive ? $0.archived : !$0.archived && !$0.pinned }
            .sorted {
                if $0.metadata.updatedAt != $1.metadata.updatedAt { return $0.metadata.updatedAt > $1.metadata.updatedAt }
                return $0.metadata.id.uuidString < $1.metadata.id.uuidString
            }
    }
    private var archivedCount: Int { store.snapshot.conversations.filter(\.archived).count }
    private var empty: Bool {
        showsAgents ? store.snapshot.agents.isEmpty : showsArchive ? conversations.isEmpty
            : store.snapshot.conversations.allSatisfy(\.archived)
    }

    // One flat collection gives UIKit a stable identity for every row, including
    // auxiliary rows that appear/disappear when the last chat is deleted.
    private var rows: [Row] {
        var result: [Row] = []
        if !showsAgents && !showsArchive {
            if !store.pinnedConversations.isEmpty { result.append(.pinned) }
            if archivedCount > 0 { result.append(.archive) }
        }
        if showsAgents { result += store.snapshot.agents.map(Row.agent) }
        else { result += conversations.map(Row.conversation) }
        if empty { result.append(.empty) }
        if store.error != nil || store.notice != nil { result.append(.feedback) }
        return result
    }

    var body: some View {
        List(rows) { row in
            switch row {
            case .pinned:
                pinnedStrip.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 16, trailing: 18))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            case .archive:
                Button { store.navigate(.archivedChats) } label: {
                    HStack(spacing: 14) {
                        BlotIcon(.archiveBox).frame(width: 50, height: 44)
                        Text(store.t("Archive")).font(.body.weight(.medium))
                        Spacer()
                        WorkspaceUnreadBadge(count: store.snapshot.conversations.filter(\.archived).reduce(0) {
                            $0 + store.chatInteractions.unreadCount(in: $1.metadata.id)
                        })
                        Text(archivedCount, format: .number).foregroundStyle(WorkspaceStyle.secondary)
                        BlotIcon(.chevronRight, size: 12).foregroundStyle(WorkspaceStyle.secondary)
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain).listRowSeparator(.hidden).listRowBackground(Color.clear)
            case .agent(let agent):
                Button { _Concurrency.Task { await store.openAgentChat(agent.metadata.id) } } label: {
                    PhoneAgentRow(agent: agent)
                }.buttonStyle(.plain)
                    .contextMenu {
                        BlotIconButton(store.t("Agent"), symbol: "person.crop.circle") { store.selectAgent(agent.metadata.id) }
                        BlotIconButton(store.t("Open chat"), symbol: "square.and.pencil") {
                            _Concurrency.Task { await store.startNewChat(with: agent.metadata.id) }
                        }
                    }
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            case .conversation(let chat):
                Button { store.openConversation(chat.metadata.id) } label: { PhoneConversationRow(conversation: chat) }
                    .buttonStyle(.plain)
                    .contextMenu { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Confirmation does not remove the row. A destructive swipe would optimistically delete it in UIKit.
                        Button { store.pendingChatDeletionID = chat.metadata.id } label: {
                            BlotLabel(store.t("Delete chat"), symbol: "trash")
                        }.tint(.red)
                        Button { store.setChatArchived(chat.metadata.id, archived: !chat.archived) } label: {
                            BlotLabel(store.t(chat.archived ? "Unarchive chat" : "Archive chat"), symbol: "archivebox")
                        }.tint(.gray)
                        Button { store.toggleChatPin(chat.metadata.id) } label: {
                            BlotLabel(store.t(chat.pinned ? "Unpin chat" : "Pin chat"), symbol: "pin")
                        }.tint(.orange)
                    }
                    .disabled(store.busy)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            case .empty:
                VStack(spacing: 16) {
                    Text(store.t(showsArchive ? "Archive is empty" : "Start a conversation")).font(.title2.weight(.semibold))
                    if !showsArchive {
                        Button(store.t(showsAgents ? "Create your first agent" : "New chat")) {
                            if showsAgents { store.beginAgentCreation() }
                            else { _Concurrency.Task { await store.startNewChat() } }
                        }.buttonStyle(WorkspaceButtonStyle())
                    }
                }.frame(maxWidth: .infinity).padding(.top, 60)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            case .feedback:
                VStack(alignment: .leading, spacing: 8) { WorkspaceFeedback() }
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .refreshable { await store.synchronizeAccount() }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
        .contentMargins(.top, 68, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollPosition(store.navigation.position(for: scrollRoute))
        .onAppear { store.navigation.restorePosition(for: scrollRoute) }
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { old, new in
            if abs(old - new) > 0.5 { store.navigation.recordOffset(new, for: scrollRoute) }
        }
        .overlay(alignment: .top) { header.padding(.horizontal, 18).padding(.top, 6) }
        .workspaceGlassContainer()
        .sheet(isPresented: $creationMenuVisible, onDismiss: presentCreation) {
            PhoneCreationMenu(createAgent: { pendingCreation = .agent; creationMenuVisible = false },
                              createGroup: { pendingCreation = .group; creationMenuVisible = false })
                .environment(store)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showsArchive {
                PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) { store.back() }
                Text(store.t("Archive")).font(.headline)
            } else if !showsAgents {
                Button { store.navigate(.settingsProfile) } label: {
                    Group {
                        if let avatar = store.profile.avatar {
                            PhoneProfileAvatar(data: avatar, size: 44)
                        } else {
                            BlotIcon(.person, size: 22).frame(width: 44, height: 44)
                        }
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel(store.settingsText("Profile"))
            }
            Spacer()
            PhoneGlassCircleButton(symbol: "magnifyingglass", title: store.t("Search")) { store.navigate(.search) }
            if !showsArchive && !showsAgents {
                PhoneGlassCircleButton(symbol: "square.and.pencil", title: store.t("Create")) { creationMenuVisible = true }
            }
            if showsAgents {
                Button { store.beginAgentCreation() } label: {
                    BlotLabel(store.t("Create"), symbol: "plus").font(.subheadline)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }.buttonStyle(.plain).accessibilityLabel(store.t("Create agent"))
            }
        }
    }

    private func presentCreation() {
        guard let creation = pendingCreation else { return }
        pendingCreation = nil
        switch creation {
        case .agent: store.beginAgentCreation()
        case .group: store.groupCreationVisible = true
        }
    }

    private var pinnedStrip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(store.pinnedConversations, id: \.metadata.id) { chat in
                    let identity = PhoneConversationIdentity(conversation: chat, agents: store.snapshot.agents, participants: store.snapshot.participants ?? [])
                    Button { store.openConversation(chat.metadata.id) } label: {
                        VStack(spacing: 8) {
                            Group {
                                if identity.isGroup { PhoneGroupAvatar(agents: identity.members, size: 70) }
                                else if let agent = identity.agent { WorkspaceAvatarView(agent: agent, size: 70) }
                                else { WorkspaceAvatar(size: 70) }
                            }
                            .overlay(alignment: .topTrailing) {
                                WorkspaceUnreadBadge(count: store.chatInteractions.unreadCount(in: chat.metadata.id),
                                    muted: store.chatInteractions.isMuted(chat.metadata.id))
                            }
                            .overlay(alignment: .bottomLeading) {
                                if !identity.isGroup { WorkspacePresenceDot(online: store.isAgentOnline(chat.agentId, in: chat.metadata.id)) }
                            }
                            Text(store.t(chat.title)).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                                .lineLimit(1).frame(width: 86)
                        }.padding(.top, 6)
                    }
                    .buttonStyle(.plain).accessibilityLabel(chat.title)
                    .contextMenu { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
                }
            }.padding(.vertical, 6)
        }.scrollIndicators(.hidden)
            .animation(.smooth(duration: 0.22), value: store.pinnedConversationIDs)
    }
}

private struct PhoneConversationRow: View {
    let conversation: BlotV3.Conversation
    @Environment(WorkspaceStore.self) private var store

    private var identity: PhoneConversationIdentity {
        .init(conversation: conversation, agents: store.snapshot.agents, participants: store.snapshot.participants ?? [])
    }
    private var agent: BlotV3.AgentProfile? { identity.agent }
    private var lastMessage: String {
        return store.snapshot.messages.last { $0.conversationId == conversation.metadata.id }.map { store.t($0.content) } ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar.frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(store.t(conversation.title)).font(.system(size: 17, weight: .medium)).lineLimit(1)
                    if conversation.pinned {
                        BlotIcon(symbol: "pin.fill", size: 11).foregroundStyle(.orange)
                            .accessibilityLabel(store.t("Pinned chat"))
                    }
                    if let tag {
                        Text(store.t(tag)).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                            .lineLimit(1).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer(minLength: 0)
                    Text(conversation.metadata.updatedAt, format: .dateTime.hour().minute())
                        .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary.opacity(0.55))
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    if store.chatActivity.isTyping(in: conversation.metadata.id) { WorkspaceTypingPreview().font(.subheadline) }
                    else { Text(lastMessage).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                    if store.chatInteractions.isMuted(conversation.metadata.id) {
                        BlotIcon(.bellOff, size: 12).foregroundStyle(WorkspaceStyle.secondary)
                    }
                    WorkspaceUnreadBadge(count: store.chatInteractions.unreadCount(in: conversation.metadata.id),
                        muted: store.chatInteractions.isMuted(conversation.metadata.id))
                }
            }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.vertical, 10).contentShape(Rectangle())
    }

    private var tag: String? {
        switch identity.isGroup ? nil : agent?.roleId {
        case "meal-planner": "Meal prepping"
        default: nil
        }
    }

    @ViewBuilder private var avatar: some View {
        if identity.isGroup { PhoneGroupAvatar(agents: identity.members, size: 48) }
        else if let agent {
            WorkspaceAvatarView(agent: agent, size: 48)
                .overlay(alignment: .bottomTrailing) {
                    WorkspacePresenceDot(online: store.isAgentOnline(agent.metadata.id, in: conversation.metadata.id), size: 11)
                }
        } else { WorkspaceAvatar(size: 48) }
    }
}
