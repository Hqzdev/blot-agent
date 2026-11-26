import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct MacLiveTeamWorkspace: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage(MacTeamPreferenceKey.sidebarWidth) private var sidebarWidth = 0.0
    @State private var settingsSearchFocusRequest = 0
    @State private var sidebarPopover = false

    private let toolbarInset: CGFloat = 14

    private var isConversation: Bool { [.home, .newChat, .chat].contains(store.route) }
    private var pageTitle: String {
        switch store.route {
        case .running: store.t("Tasks")
        case .approval: store.t("Approval")
        case .result: store.t("Result")
        case .offline: store.t("Your computer is offline")
        case .file: store.selectedFile?.name ?? store.t("Files")
        default: store.t(store.route.title)
        }
    }
    private var agent: BlotV3.AgentProfile? {
        store.chatContent.agents.first { $0.metadata.id == (store.currentConversation?.agentId ?? store.selectedAgentID) }
    }
    private var members: [BlotV3.AgentProfile] {
        let ids = Set(store.chatContent.participants.filter { $0.conversationId == store.selectedConversationID && !$0.removed }.map(\.participantId))
        return store.chatContent.agents.filter { ids.contains($0.metadata.id) }
    }
    var body: some View {
        GeometryReader { geometry in
            if let route = store.settingsRoute {
                MacLiveTeamSettings(route: route, searchFocusRequest: settingsSearchFocusRequest).id(route).transition(.kAppear)
            } else { workspace(layout: MacWorkspaceLayout(size: geometry.size, preferredSidebarWidth: sidebarWidth > 0 ? CGFloat(sidebarWidth) : nil)) }
        }
        .macHoverTipHost()
        .kAnimation(KMotion.panel, value: store.settingsRoute)
        .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.ink).background(MacChatStyle.canvas)
        .frame(minWidth: store.browser?.presented == true && isConversation ? MacBrowserSplitLayout.minimumWidth : MacWorkspaceLayout.minimumWidth, minHeight: MacWorkspaceLayout.minimumHeight)
        .toolbar(removing: .title).toolbarVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top).teamControls()
        .overlay(alignment: .topLeading) {
            GeometryReader { _ in
                MacTeamNativeWindowButtons().frame(width: 60, height: 16).padding(.leading, 16).padding(.top, 14)
            }.ignoresSafeArea(.container, edges: .top)
        }
        .focusedSceneValue(\.teamSceneActions, MacTeamSceneActions(
            createAgent: { store.settingsRoute = nil; store.navigate(.createAgent) }, settings: { store.navigate(.settings) },
            back: { if store.settingsRoute != nil { store.settingsRoute = nil } else { store.back() } },
            search: { if store.settingsRoute != nil { settingsSearchFocusRequest += 1 } else { store.navigate(.search) } }, canSearch: true))
        .workspacePanelSheet(isPresented: Binding(get: { store.pendingBranchMessageID != nil }, set: { if !$0 { store.pendingBranchMessageID = nil } })) {
            if let id = store.pendingBranchMessageID { WorkspaceBranchAgentPicker(messageID: id).environment(store) }
        }
    }
    private func workspace(layout: MacWorkspaceLayout) -> some View {
        let showsBrowser = store.browser?.presented == true && isConversation
        let showsSidebar = layout.supportsSidebar && store.sidebarVisible
        let sidebarBounds = layout.sidebarBounds(computerVisible: showsBrowser)
        let leftWidth = min(layout.sidebarWidth, sidebarBounds.upperBound)
        return HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                if showsSidebar {
                    MacLiveTeamSidebar().environment(\.blotChatChrome, isConversation)
                        .frame(width: leftWidth).background(MacChatStyle.sidebar)
                        .transition(.opacity)
                }
            }
            .frame(width: showsSidebar ? leftWidth : 0, alignment: .trailing)
            .clipped()
            .allowsHitTesting(showsSidebar)
            .accessibilityHidden(!showsSidebar)
            .overlay(alignment: .trailing) {
                if showsSidebar {
                    MacWorkspaceDivider(width: Binding(get: { Double(leftWidth) }, set: { sidebarWidth = $0 }),
                        bounds: Double(sidebarBounds.lowerBound)...Double(sidebarBounds.upperBound),
                        title: store.language == "ru" ? "Ширина списка чатов" : "Chat list width")
                        .offset(x: MacWorkspaceDivider.hitWidth / 2)
                }
            }
            .zIndex(1)
            MacBrowserSplitView(isPresented: showsBrowser) {
                conversation(showsSidebar: showsSidebar, showsBrowser: showsBrowser, layout: layout)
            } browser: {
                if let browser = store.browser {
                    WorkspaceBrowserView(controller: browser, trailingTabInset: MacChatIconButton.size + toolbarInset)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isConversation {
                    VStack(alignment: .trailing, spacing: 8) {
                        computerButton(panelOpen: showsBrowser)
                        if !showsBrowser, let tab = store.browser?.agentSiteTab, let host = tab.url?.host {
                            agentSiteButton(tab, host: host)
                        }
                    }.padding(.trailing, toolbarInset).padding(.top, 13)
                }
            }
        }
        .kAnimation(KMotion.sidebar, value: showsSidebar)
        .kAnimation(KMotion.panel, value: showsBrowser)
        .onChange(of: store.route) { _, _ in sidebarPopover = false }
        .onChange(of: layout.supportsSidebar) { _, _ in sidebarPopover = false }
        .onChange(of: store.selectedConversationID) { _, _ in sidebarPopover = false }
    }

    private func sidebarToggleTitle(visible: Bool) -> String {
        if store.language == "ru" { return visible ? "Скрыть боковую панель" : "Показать боковую панель" }
        return visible ? "Hide sidebar" : "Show sidebar"
    }

    private func computerButton(panelOpen: Bool) -> some View {
        let russian = store.language == "ru"
        let title = panelOpen ? (russian ? "Закрыть компьютер" : "Close computer") : (russian ? "Открыть компьютер" : "Open computer")
        return GlassEffectContainer {
            MacChatIconButton(title: title, symbol: "desktopcomputer") { store.toggleToolsPanel() }
                .accessibilityIdentifier("workspace.computer.toggle")
        }.environment(\.blotChatChrome, true)
    }

    private func agentSiteButton(_ tab: BrowserTab, host: String) -> some View {
        let russian = store.language == "ru"
        let title = tab.loading || tab.title.isEmpty || tab.title == "Новая вкладка" ? host : tab.title
        let status = if tab.loading { russian ? "Загружается" : "Loading" }
            else if tab.error != nil { russian ? "Ошибка загрузки" : "Loading failed" }
            else { host }
        return Button {
            do { try store.showBrowserTab(tab.id) }
            catch { store.error = error.localizedDescription }
        } label: {
            HStack(spacing: 9) {
                if tab.loading { ProgressView().controlSize(.small) }
                else { BlotIcon(symbol: "globe", size: 17).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.callout.weight(.medium)).lineLimit(1)
                    if status != title { Text(verbatim: status).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                BlotIcon(symbol: "sidebar.right", size: 14).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(width: 222, alignment: .leading)
            .blotChromeSurface(cornerRadius: 15)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((russian ? "Открыть сайт агента: " : "Open the agent's website: ") + host)
        .accessibilityValue(status)
        .accessibilityIdentifier("workspace.computer.agent-site")
    }

    private func conversation(showsSidebar: Bool, showsBrowser: Bool, layout: MacWorkspaceLayout) -> some View {
        ZStack(alignment: .top) {
            if isConversation { MacLiveTeamConversation(messages: store.currentVisibleMessages).id(store.selectedConversationID) }
            else { WorkspacePage(route: store.route).id(store.route).transition(.kAppear).padding(.top, 66) }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        if !showsSidebar { Color.clear.frame(width: 68) }
                        MacChatIconButton(title: sidebarToggleTitle(visible: showsSidebar || sidebarPopover), symbol: "sidebar.left") {
                            if layout.supportsSidebar { store.sidebarVisible.toggle() } else { sidebarPopover.toggle() }
                        }
                        .popover(isPresented: $sidebarPopover) { MacLiveTeamSidebar().frame(width: MacWorkspaceLayout.defaultSidebarWidth, height: layout.popoverHeight).macHoverTipHost().environment(store) }
                    }.frame(width: showsSidebar ? 40 : 116, alignment: .leading)
                    Spacer(minLength: 0)
                    if isConversation {
                        Button {
                            if let chat = store.currentConversation, chat.kind == .group { store.editGroup(chat.metadata.id) }
                            else if let agent { store.selectAgent(agent.metadata.id, destination: .editAgent) }
                        } label: {
                            HStack(spacing: 9) {
                                if store.currentConversation?.kind == .group { MacLiveTeamGroupAvatar(agents: members, size: 30) }
                                Text(store.currentConversation?.title ?? agent?.name ?? "Ori")
                                    .font(.system(size: 14, weight: .semibold)).lineLimit(1).contentTransition(.interpolate)
                            }.padding(.horizontal, 14).frame(height: 44)
                                .blotChromeSurface(cornerRadius: 24).blotHitArea()
                        }.buttonStyle(BlotHitTargetButtonStyle(hoverIn: Capsule()))
                            .macHoverTip(store.currentConversation?.title ?? agent?.name ?? "Ori")
                    } else {
                        Text(pageTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 14).frame(height: 44)
                    }
                    Spacer(minLength: 0)
                    if isConversation {
                        Color.clear
                            .frame(width: max(showsSidebar ? 40 : 116, showsBrowser ? 0 : MacChatIconButton.size), height: 1)
                            .accessibilityHidden(true)
                    } else {
                        MacChatIconButton(title: store.t("Back"), symbol: "chevron.left") { store.back() }
                            .frame(width: showsSidebar ? 40 : 116, alignment: .trailing)
                    }
                }
            }.environment(\.blotChatChrome, isConversation).fixedSize(horizontal: false, vertical: true).padding(.horizontal, toolbarInset).padding(.top, 10)
                .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
        }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .kAnimation(KMotion.panel, value: store.route)
    }
}

struct MacChatCreateButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        MacChatIconButton(title: store.t("Create"), symbol: "plus") { showing.toggle() }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                MacActionMenuPanel {
                    BlotIconButton(store.t("Create agent"), symbol: "person.badge.plus") { store.navigate(.createAgent) }
                    BlotIconButton(store.t("Create group"), symbol: "person.2") { store.groupCreationVisible = true }
                }.buttonStyle(MacMenuDismissStyle(close: { showing = false }))
            }
    }
}

private struct MacLiveTeamSidebar: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""
    @State private var profileOpen = false
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool
    private var pinnedChats: [BlotV3.Conversation] {
        let pins = store.pinnedConversations
        guard !query.isEmpty else { return pins }
        return pins.filter { chat in
            matches(chat.title, message: lastMessage(chat.metadata.id)?.content)
                || store.chatContent.agents.contains { $0.metadata.id == chat.agentId && $0.name.localizedCaseInsensitiveContains(query) }
        }
    }
    private var groups: [BlotV3.Conversation] {
        store.snapshot.conversations.filter { !$0.archived && !$0.pinned && $0.kind == .group && matches($0.title, message: lastMessage($0.metadata.id)?.content) }
    }
    private var agents: [AgentRow] {
        store.snapshot.agents.compactMap { agent in
            let chat = latestChat(with: agent.metadata.id)
            guard chat?.pinned != true, matches(agent.name, message: lastMessage(chat?.metadata.id)?.content) else { return nil }
            return AgentRow(agent: agent, chat: chat)
        }
    }

    private struct AgentRow: Identifiable {
        let agent: BlotV3.AgentProfile
        let chat: BlotV3.Conversation?
        var id: UUID { agent.metadata.id }
    }

    var body: some View {
        let pinnedChats = pinnedChats
        let groups = groups
        let agents = agents
        let searchTitle = store.language == "ru" ? "Фильтр чатов" : "Filter chats"
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Spacer()
                    MacChatIconButton(title: searchTitle, symbol: "magnifyingglass") {
                        searchVisible.toggle(); searchFocused = searchVisible
                        if !searchVisible { query = "" }
                    }
                    MacChatCreateButton()
                }.macSidebarHoverSection(radius: 19).padding(.horizontal, 16).frame(height: 64)
            }.background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
            if searchVisible {
                VStack(alignment: .leading, spacing: 7) {
                    TextField(searchTitle, text: $query).textFieldStyle(BlotTextFieldStyle()).focused($searchFocused)
                    Button(store.language == "ru" ? "Искать по сообщениям" : "Search messages") {
                        if !query.isEmpty { store.form.search.query = query }
                        store.navigate(.search)
                    }.buttonStyle(BlotSecondaryTextButtonStyle())
                }.padding(.horizontal, 14).padding(.bottom, 10)
            }
            if !pinnedChats.isEmpty {
                MacPinnedChats(chats: pinnedChats).padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    if query.isEmpty, store.snapshot.conversations.contains(where: \.archived) {
                        Button { store.navigate(.archivedChats) } label: {
                            HStack(spacing: 9) {
                                BlotIcon(.archiveBox, size: BlotIconSize.control)
                                Text(store.language == "ru" ? "Архив чатов" : "Archived chats")
                                Spacer()
                            }
                        }.buttonStyle(WorkspaceRowButtonStyle())
                    }
                    ForEach(groups, id: \.metadata.id) { chat in
                        row(title: chat.title, chatID: chat.metadata.id, selected: store.selectedConversationID == chat.metadata.id) {
                            MacLiveTeamGroupAvatar(agents: members(of: chat), size: 40)
                        } action: { store.openConversation(chat.metadata.id) }
                            .modifier(MacTeamPressMenu(secondaryClick: true, preservesTap: true, surface: .sidebar) { close in
                                WorkspaceChatActionsMenu(chat: chat).environment(store).buttonStyle(MacMenuDismissStyle(close: close))
                            })
                    }
                    ForEach(agents) { entry in
                        let agent = entry.agent
                        row(title: agent.name, role: agent.roleId == "custom" ? nil : agent.roleId.replacingOccurrences(of: "-", with: " ").capitalized,
                            chatID: entry.chat?.metadata.id, selected: entry.chat?.metadata.id == store.selectedConversationID && entry.chat != nil) {
                            WorkspaceAvatarView(agent: agent, size: 40)
                        } action: { _Concurrency.Task { await store.openAgentChat(agent.metadata.id) } }
                        .modifier(MacTeamPressMenu(secondaryClick: true, preservesTap: true, surface: .sidebar) { close in
                            Group {
                                if let chat = entry.chat { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
                                else {
                                    BlotIconButton(store.t("Edit agent"), symbol: "paintbrush") { store.editChatAgent(agent.metadata.id) }
                                }
                            }.buttonStyle(MacMenuDismissStyle(close: close))
                        })
                    }
                    if agents.isEmpty && groups.isEmpty && pinnedChats.isEmpty {
                        Text(store.t(query.isEmpty ? "Create your first agent" : "No results")).font(.caption).foregroundStyle(.secondary).padding(20)
                    }
                }.padding(.horizontal, 5)
            }.scrollIndicators(.hidden).macSidebarHoverSection(radius: 14)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button { profileOpen.toggle() } label: {
                        Text(String(store.accountDisplayName.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()).font(.system(size: 12, weight: .medium))
                            .frame(width: 38, height: 38)
                            .background(WorkspaceStyle.surface, in: Circle())
                            .overlay(Circle().strokeBorder(BlotColor.hairline)).blotHitArea()
                    }.buttonStyle(BlotHitTargetButtonStyle(hoverIn: Circle(), hoverColor: .clear)).macSidebarHoverTarget().accessibilityLabel(store.t("Profile")).macHoverTip(store.t("Profile"))
                    .popover(isPresented: $profileOpen, arrowEdge: .bottom) {
                        MacSidebarProfileMenu { profileOpen = false }
                            .environment(store)
                            .onExitCommand { profileOpen = false }
                    }
                    MacWorkspacePillButton(action: { store.navigate(.marketplace) }) {
                        HStack(spacing: 8) {
                            Text(store.t("Connect apps"))
                            HStack(spacing: -3) {
                                ForEach(["PluginNotion", "PluginDrive"], id: \.self) { asset in
                                    Image(asset).resizable().scaledToFit().frame(width: 14, height: 14)
                                        .padding(1).background(.white, in: RoundedRectangle(cornerRadius: 5))
                                }
                            }.accessibilityHidden(true)
                        }
                    }.macHoverTip(store.t("Connect apps"))
                }.macSidebarHoverSection(radius: 19).padding(.horizontal, 14).padding(.vertical, 14)
            }
        }.kAnimation(KMotion.panel, value: searchVisible)
    }
    private func row<Avatar: View>(title: String, role: String? = nil, chatID: UUID?, selected: Bool, @ViewBuilder avatar: () -> Avatar, action: @escaping () -> Void) -> some View {
        let message = lastMessage(chatID)
        let unread = chatID.map { store.chatInteractions.unreadCount(in: $0) > 0 } ?? false
        let running = chatID.map { store.chatContent.runningTaskConversationIDs.contains($0) } ?? false
        return Button(action: action) {
            HStack(spacing: 10) {
                avatar().overlay(alignment: .bottomTrailing) { if running { Circle().fill(.green).frame(width: 7, height: 7).overlay(Circle().stroke(MacChatStyle.sidebar, lineWidth: 1)) } }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 5) {
                                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                if let role {
                                    Text(store.t(role)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(MacChatStyle.incoming, in: Capsule())
                                }
                            }
                            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        }
                        Spacer(minLength: 0)

                    }
                    HStack(spacing: 4) {
                        Text(message?.content ?? "").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        if unread { Circle().fill(.blue).frame(width: 6, height: 6) }
                    }
                }
            }.padding(.horizontal, 9).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected && store.route == .chat ? MacChatStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
        }.buttonStyle(BlotPlainButtonStyle(showsHover: false)).macSidebarHoverTarget()
            .kAnimation(KMotion.standard, value: selected).macHoverTip(message.map { title + " · " + timestamp($0.metadata.createdAt) } ?? title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func timestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        if Calendar.current.isDateInYesterday(date) { return store.language == "ru" ? "Вчера" : "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    private func matches(_ name: String, message: String?) -> Bool { query.isEmpty || name.localizedCaseInsensitiveContains(query) || (message?.localizedCaseInsensitiveContains(query) ?? false) }
    private func latestChat(with agentID: UUID) -> BlotV3.Conversation? {
        store.snapshot.conversations.lazy.filter { !$0.archived && $0.kind != .group && $0.agentId == agentID }
            .max { $0.metadata.updatedAt < $1.metadata.updatedAt }
    }
    private func lastMessage(_ id: UUID?) -> BlotV3.Message? { store.latestVisibleMessage(in: id) }
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
                BlotIcon(symbol: "person.2.fill").font(.system(size: size * 0.4)).foregroundStyle(.secondary)
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
