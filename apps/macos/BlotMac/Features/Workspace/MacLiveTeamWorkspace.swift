import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

/// The approved team layout, driven exclusively by the authenticated workspace.
struct MacLiveTeamWorkspace: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var settingsSearchFocusRequest = 0
    @State private var creating = false
    @State private var sidebarPopover = false

    private var isConversation: Bool { [.home, .newChat, .chat].contains(store.route) }
    private var agent: BlotV3.AgentProfile? {
        store.snapshot.agents.first { $0.metadata.id == (store.currentConversation?.agentId ?? store.selectedAgentID) }
    }
    private var members: [BlotV3.AgentProfile] {
        let ids = Set((store.snapshot.participants ?? []).filter { $0.conversationId == store.selectedConversationID && !$0.removed }.map(\.participantId))
        return store.snapshot.agents.filter { ids.contains($0.metadata.id) }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let route = store.settingsRoute {
                    MacLiveTeamSettings(route: route, searchFocusRequest: settingsSearchFocusRequest).transition(.opacity)
                } else { workspace(layout: MacWorkspaceLayout(size: geometry.size)).transition(.opacity) }
            }
        }
        .kAnimation(KMotion.panel, value: store.settingsRoute != nil)
        .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.ink).background(WorkspaceStyle.canvas)
        .frame(minWidth: store.browser?.presented == true && isConversation ? MacBrowserSplitLayout.minimumWidth : MacWorkspaceLayout.minimumWidth,
               minHeight: MacWorkspaceLayout.minimumHeight)
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

    private func workspace(layout: MacWorkspaceLayout) -> some View {
        let showsBrowser = store.browser?.presented == true && isConversation
        let showsSidebar = layout.supportsSidebar && store.sidebarVisible
        return HStack(spacing: 0) {
            if showsSidebar {
                MacLiveTeamSidebar().frame(width: layout.sidebarWidth).background(MacTeamStyle.sidebar).transition(.kPanel(.leading))
            }
            if showsBrowser, let browser = store.browser {
                MacBrowserSplitView {
                    conversation(layout: layout, showsSidebar: showsSidebar)
                } browser: {
                    WorkspaceBrowserView(controller: browser, compact: true)
                }
            } else { conversation(layout: layout, showsSidebar: showsSidebar) }
        }
        .kAnimation(KMotion.sidebar, value: showsSidebar)
        .kAnimation(KMotion.panel, value: store.selectedConversationID)
        .onChange(of: store.route) { _, _ in sidebarPopover = false }
        .onChange(of: store.selectedConversationID) { _, _ in sidebarPopover = false }
        .onChange(of: layout.supportsSidebar) { _, _ in sidebarPopover = false }
    }

    private func conversation(layout: MacWorkspaceLayout, showsSidebar: Bool) -> some View {
        VStack(spacing: 0) {
            header(layout: layout, showsSidebar: showsSidebar)
            if isConversation { MacLiveTeamConversation(messages: store.currentMessages).id(store.selectedConversationID).transition(.opacity) }
            else { WorkspacePage(route: store.route) }
        }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(layout: MacWorkspaceLayout, showsSidebar: Bool) -> some View {
        GlassEffectContainer(spacing: 8) {
            ZStack {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        if store.route == .marketplace {
                            Text(store.t(store.route.title))
                                .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        } else {
                            if store.currentConversation?.kind == .group { MacLiveTeamGroupAvatar(agents: members, size: 36) }
                            else if let agent { WorkspaceAvatarView(agent: agent, size: 36) }
                            Text(store.currentConversation?.title ?? agent?.name ?? "Blot")
                                .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                    if isConversation {
                        if store.currentConversation?.kind == .group { MacLiveTeamGroupAvatar(agents: members, size: 36) }
                        else if let agent { WorkspaceAvatarView(agent: agent, size: 36) }
                    }
                    Color.clear.frame(width: 0, height: 0)
                }.padding(.leading, showsSidebar ? 100 : 200).padding(.trailing, isConversation ? 104 : 64)
                HStack(spacing: 6) {
                    if store.route == .marketplace {
                        headerButton(store.t("Back"), glyph: .chevronLeft) { store.back() }
                    }
                    headerButton("Боковая панель", glyph: .layout) {
                        if layout.supportsSidebar { store.sidebarVisible.toggle() }
                        else { sidebarPopover.toggle() }
                    }
                    .popover(isPresented: $sidebarPopover, arrowEdge: .top) {
                        MacLiveTeamSidebar(showsWindowSpace: false)
                            .frame(width: 280, height: layout.popoverHeight).environment(store)
                    }
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
                    if isConversation { WorkspaceVoiceButton() }
                    if isConversation {
                        headerButton("Инструменты", glyph: .inspector) {
                            store.toggleToolsPanel()
                        }
                    }
                }.padding(.leading, showsSidebar ? 18 : 108).padding(.trailing, 18)
            }.padding(.top, 14).frame(height: 64, alignment: .top)
        }
        .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()).allowsWindowActivationEvents(true) }
    }

    private func headerButton(_ title: String, glyph: BlotGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) { BlotIcon(glyph, size: BlotIconSize.control).frame(width: 36, height: 36) }
            .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle).accessibilityLabel(Text(LocalizedStringKey(title))).help(Text(LocalizedStringKey(title)))
    }
}

private struct MacLiveTeamSidebar: View {
    var showsWindowSpace = true
    @Environment(WorkspaceStore.self) private var store
    private var groups: [BlotV3.Conversation] {
        store.snapshot.conversations.filter { chat in
            !chat.archived && chat.kind == .group
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            if showsWindowSpace {
                Color.clear.frame(height: 64).contentShape(Rectangle()).gesture(WindowDragGesture())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    heading("Команда")
                    ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                        MacTeamNavigationButton(selected: store.currentConversation?.kind != .group && store.selectedAgentID == agent.metadata.id && store.route == .chat,
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
                            Button("Открыть чат") { _Concurrency.Task { await store.newChat(with: agent.metadata.id) } }
                            if let chat = store.currentConversation, chat.kind != .group, chat.agentId == agent.metadata.id {
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
                            MacTeamNavigationButton(selected: store.route == .chat && store.selectedConversationID == chat.metadata.id,
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
                MacTeamNavigationButton(selected: store.route == .marketplace, action: {
                    if store.route != .marketplace { store.navigate(.marketplace) }
                }) {
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
        WorkspaceLocalizedText(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }
    private func lastMessage(for agent: BlotV3.AgentProfile) -> String {
        let ids = Set(store.snapshot.conversations.filter { $0.kind != .group && $0.agentId == agent.metadata.id }.map(\.metadata.id))
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
            if agents.isEmpty {
                Image(systemName: "person.2.fill").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
            } else if agents.count == 1, let agent = agents.first {
                WorkspaceAvatarView(agent: agent, size: size)
            } else {
                ForEach(Array(agents.prefix(2).enumerated()), id: \.element.metadata.id) { index, agent in
                    WorkspaceAvatarView(agent: agent, size: size * 0.64)
                        .offset(x: index == 0 ? -size * 0.16 : size * 0.16, y: index == 0 ? -size * 0.16 : size * 0.16)
                }
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
