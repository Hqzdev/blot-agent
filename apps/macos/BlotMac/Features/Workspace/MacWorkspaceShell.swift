import BlotDesign
import BlotDomain
import SwiftUI

struct MacWorkspaceShell: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        if store.mode == .preview && ProcessInfo.processInfo.arguments.contains("--team-design") {
            MacTeamWorkspace()
        } else if store.mode == .live {
            MacLiveTeamWorkspace()
        } else {
            referenceShell
        }
    }

    private var referenceShell: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if store.sidebarVisible {
                    MacWorkspaceSidebar().frame(width: MacWorkspaceStyle.sidebarWidth)
                    Divider()
                }
                VStack(spacing: 0) {
                    header
                    WorkspacePage(route: store.mode == .preview && store.route.isSetting ? .chat : store.route)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.inspectorVisible && [.chat, .blocked].contains(store.route) {
                    Divider()
                    MacWorkspaceInspector().frame(width: min(MacWorkspaceStyle.inspectorWidth, geometry.size.width * 0.31))
                }
            }
        }
        .font(MacWorkspaceStyle.body).background(WorkspaceStyle.canvas)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !store.sidebarVisible {
                Button { store.sidebarVisible = true } label: { BlotIcon(.layout, size: 15) }
                    .buttonStyle(.plain).help(store.t("Show chats"))
            }
            if [.createAgent, .editAgent, .firstAgent].contains(store.route) {
                WorkspaceAvatar(shape: .init(rawValue: store.form.agent.shape) ?? .round,
                    color: WorkspaceAvatarView.color(store.form.agent.color), size: 24)
                Text(store.form.agent.name.isEmpty ? store.t("New agent") : store.form.agent.name)
                    .font(.system(size: 14, weight: .medium)).lineLimit(1)
            } else if let agent = store.snapshot.agents.first(where: { $0.metadata.id == store.currentConversation?.agentId }), store.route == .chat {
                Button { store.selectAgent(agent.metadata.id) } label: {
                    HStack(spacing: 7) {
                        WorkspaceAvatarView(agent: agent, size: 24)
                            .overlay(alignment: .bottomTrailing) {
                                WorkspacePresenceDot(online: store.isAgentOnline(agent.metadata.id, in: store.selectedConversationID), size: 7)
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            if let id = store.selectedConversationID, store.chatActivity.isTyping(in: id) {
                                WorkspaceTypingPreview().font(.system(size: 10))
                            } else {
                                Text(store.t(store.isAgentOnline(agent.metadata.id, in: store.selectedConversationID) ? "Online" : "Not online"))
                                    .font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary)
                            }
                        }
                    }
                }.buttonStyle(.plain)
            } else {
                Text(store.t(store.route.title)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            Spacer()
            if store.route == .chat {
                Button { _Concurrency.Task { await store.newChat(with: store.currentConversation?.agentId) } } label: { BlotIcon(.compose, size: 15) }
                    .buttonStyle(.plain).help(store.t("New chat")).accessibilityLabel(store.t("New chat")).disabled(store.busy)
                if let chat = store.currentConversation {
                    Menu { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) } label: { BlotIcon(.more, size: 15) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(store.t("Chat actions"))
                }
                Button { store.inspectorVisible.toggle() } label: { BlotIcon(.computer, size: 16) }
                    .buttonStyle(.plain).help(store.t("Agent panel"))
            } else if store.route == .agents {
                Button { store.navigate(.createAgent) } label: { BlotIcon(.plus, size: 15) }
                    .buttonStyle(.plain).help(store.t("Create agent"))
            } else if store.route == .schedules {
                Button { store.navigate(.createSchedule) } label: { BlotIcon(.plus, size: 15) }
                    .buttonStyle(.plain).help(store.t("Create schedule"))
            }
        }.padding(.horizontal, 16).frame(height: 44)
            .background(WorkspaceStyle.canvas)
            .overlay(alignment: .bottom) { Rectangle().fill(MacWorkspaceStyle.edge).frame(height: 1) }
    }
}
