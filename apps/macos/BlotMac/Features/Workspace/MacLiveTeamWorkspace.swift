import BlotDesign
import BlotDomain
import SwiftUI

/// The approved team layout, driven exclusively by the authenticated workspace.
struct MacLiveTeamWorkspace: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var inspectorVisible = true
    @State private var settingsSearchFocusRequest = 0
    @State private var creating = false

    private var isConversation: Bool { [.home, .newChat, .chat].contains(store.route) }
    private var agent: BlotV3.AgentProfile? {
        store.snapshot.agents.first { $0.metadata.id == (store.currentConversation?.agentId ?? store.selectedAgentID) }
    }
    private var members: [BlotV3.AgentProfile] {
        let ids = Set((store.snapshot.participants ?? []).filter { $0.conversationId == store.selectedConversationID && !$0.removed }.map(\.participantId))
        return store.snapshot.agents.filter { ids.contains($0.metadata.id) }
    }

    var body: some View {
        ZStack {
            if let route = store.settingsRoute {
                MacLiveTeamSettings(route: route, searchFocusRequest: settingsSearchFocusRequest).transition(.opacity)
            } else { workspace.transition(.opacity) }
        }
        .kAnimation(KMotion.panel, value: store.settingsRoute != nil)
        .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.ink).background(WorkspaceStyle.canvas)
        .frame(minWidth: 1100, minHeight: 700)
        .toolbar(removing: .title).toolbarVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top).teamControls()
        .overlay(alignment: .topLeading) {
            GeometryReader { _ in
                MacTeamNativeWindowButtons().frame(width: 60, height: 16)
                    .padding(.leading, 24).padding(.top, 24)
            }.ignoresSafeArea(.container, edges: .top)
        }
        .focusedSceneValue(\.teamSceneActions, MacTeamSceneActions(
            createAgent: { store.settingsRoute = nil; store.navigate(.createAgent) }, settings: { store.navigate(.settings) },
            back: { if store.settingsRoute != nil { store.settingsRoute = nil } else { store.back() } },
            search: { if store.settingsRoute != nil { settingsSearchFocusRequest += 1 } else { store.navigate(.search) } }, canSearch: true))
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            if store.sidebarVisible {
                MacLiveTeamSidebar().frame(width: 252).background(MacTeamStyle.sidebar).transition(.kPanel(.leading))
            }
            VStack(spacing: 0) {
                header
                if isConversation { MacLiveTeamConversation(messages: store.currentMessages).id(store.selectedConversationID).transition(.opacity) }
                else { WorkspacePage(route: store.route) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if inspectorVisible && isConversation {
                MacLiveTeamInspector().frame(width: 306).background(MacTeamStyle.sidebar).transition(.kPanel(.trailing))
            }
        }
        .kAnimation(KMotion.sidebar, value: store.sidebarVisible)
        .kAnimation(KMotion.sidebar, value: inspectorVisible && isConversation)
        .kAnimation(KMotion.panel, value: store.selectedConversationID)
    }

    private var header: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack {
                HStack(spacing: 8) {
                    if members.count > 1 { MacLiveTeamGroupAvatar(agents: members, size: 36) }
                    else if let agent { WorkspaceAvatarView(agent: agent, size: 36) }
                    Text(store.currentConversation?.title ?? agent?.name ?? "Blot")
                        .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }.padding(.horizontal, 100)
                HStack(spacing: 6) {
                    headerButton("Боковая панель", glyph: .layout) { store.sidebarVisible.toggle() }
                    Button { creating.toggle() } label: {
                        BlotIcon(.plus, size: BlotIconSize.control).frame(width: 36, height: 36)
                    }.buttonStyle(.plain).opacity(creating ? 0 : 1)
                        .glassEffect(.regular.interactive(), in: .circle).accessibilityLabel("Создать")
                        .background {
                            MacTeamToolbarExpansion(isPresented: $creating, size: CGSize(width: 192, height: 128)) {
                                MacTeamCreateMenu(close: { creating = false }) { sheet in
                                    creating = false
                                    switch sheet {
                                    case .newAgent: store.navigate(.createAgent)
                                    case .group: store.groupCreationVisible = true
                                    default: break
                                    }
                                }
                                .environment(\.blotReduceMotion, reduceMotion)
                            }.frame(width: 36, height: 36)
                        }
                    Spacer()
                    if isConversation { headerButton("Панель агента", glyph: .inspector) { inspectorVisible.toggle() } }
                }.padding(.leading, store.sidebarVisible ? 18 : 108).padding(.trailing, 18)
            }.padding(.top, 14).frame(height: 64, alignment: .top)
        }
        .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()).allowsWindowActivationEvents(true) }
    }

    private func headerButton(_ title: String, glyph: BlotGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) { BlotIcon(glyph, size: BlotIconSize.control).frame(width: 36, height: 36) }
            .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle).accessibilityLabel(title).help(title)
    }
}

private struct MacLiveTeamSidebar: View {
    @Environment(WorkspaceStore.self) private var store
    private var groups: [BlotV3.Conversation] {
        store.snapshot.conversations.filter { chat in
            !chat.archived && (store.snapshot.participants ?? []).filter { $0.conversationId == chat.metadata.id && !$0.removed && $0.kind == .agent }.count > 1
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 64).contentShape(Rectangle()).gesture(WindowDragGesture())
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    heading("Команда")
                    ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                        MacTeamNavigationButton(selected: store.selectedAgentID == agent.metadata.id && store.route == .chat,
                            action: { _Concurrency.Task { await store.openAgentChat(agent.metadata.id) } }) {
                            HStack(spacing: 10) {
                                WorkspaceAvatarView(agent: agent, size: 36)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(agent.name).font(.system(size: 12, weight: .medium))
                                    Text(lastMessage(for: agent)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }.contextMenu {
                            Button("Настроить агента") { store.selectAgent(agent.metadata.id, destination: .editAgent) }
                            Button("Новый чат") { _Concurrency.Task { await store.newChat(with: agent.metadata.id) } }
                            if let chat = store.currentConversation, chat.agentId == agent.metadata.id {
                                Divider()
                                WorkspaceChatActionsMenu(chat: chat).environment(store)
                            }
                        }
                    }
                    if store.snapshot.agents.isEmpty {
                        MacTeamNavigationButton(action: { store.navigate(.createAgent) }) {
                            Label("Создать своего агента", systemImage: "plus").font(.system(size: 12))
                        }
                    }
                    if !groups.isEmpty {
                        heading("Группы").padding(.top, 16)
                        ForEach(groups, id: \.metadata.id) { chat in
                            MacTeamNavigationButton(selected: store.selectedConversationID == chat.metadata.id,
                                action: { store.openConversation(chat.metadata.id) }) {
                                HStack(spacing: 10) {
                                    MacLiveTeamGroupAvatar(agents: members(of: chat), size: 36)
                                    Text(chat.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                }
                            }.contextMenu { WorkspaceChatActionsMenu(chat: chat).environment(store) }
                        }
                    }
                }.padding(.horizontal, 10).padding(.bottom, 16)
            }.scrollIndicators(.hidden)
            VStack(spacing: 6) {
                MacTeamNavigationButton(action: { store.navigate(.connections) }) {
                    Label("Приложения и шаблоны", systemImage: "square.grid.2x2").font(.system(size: 12))
                }
                Divider()
                MacTeamNavigationButton(action: { store.navigate(.settings) }) {
                    HStack(spacing: 10) {
                        Text(String(store.accountDisplayName.prefix(1))).font(.system(size: 10, weight: .medium))
                            .frame(width: 28, height: 28).background(.quaternary, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.accountDisplayName).font(.system(size: 12, weight: .medium))
                            Text("Личное пространство").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BlotIcon(.settings, size: BlotIconSize.control)
                    }
                }
            }.padding(.horizontal, 10).padding(.bottom, 12)
        }
    }
    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }
    private func lastMessage(for agent: BlotV3.AgentProfile) -> String {
        let ids = Set(store.snapshot.conversations.filter { $0.agentId == agent.metadata.id }.map(\.metadata.id))
        return store.snapshot.messages.last { ids.contains($0.conversationId) }?.content ?? agent.instructions
    }
    private func members(of chat: BlotV3.Conversation) -> [BlotV3.AgentProfile] {
        let ids = Set((store.snapshot.participants ?? []).filter { $0.conversationId == chat.metadata.id && !$0.removed }.map(\.participantId))
        return store.snapshot.agents.filter { ids.contains($0.metadata.id) }
    }
}

struct MacLiveTeamGroupAvatar: View {
    let agents: [BlotV3.AgentProfile]
    var size: CGFloat
    var body: some View {
        ZStack {
            ForEach(Array(agents.prefix(2).enumerated()), id: \.element.metadata.id) { index, agent in
                WorkspaceAvatarView(agent: agent, size: size * 0.64)
                    .offset(x: index == 0 ? -size * 0.16 : size * 0.16, y: index == 0 ? -size * 0.16 : size * 0.16)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
