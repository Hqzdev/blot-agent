import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspacePage: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        GeometryReader { geometry in
            Group {
                if store.screenState != .normal {
                    ScrollView { WorkspaceDataState(state: store.screenState).padding(24) }
                } else if usesAuthenticationLayout {
                    WorkspaceAuthView(route: route)
                } else {
                    page(height: geometry.size.height)
                }
            }
            .workspaceGlassContainer()
            #if os(iOS)
            .onAppear {
                if route != .chat && route != .home { PhoneKeyboard.dismiss() }
            }
            #endif
            .background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink)
            .accessibilityIdentifier("workspace.screen.\(route.rawValue)")
        }
    }
    private var usesAuthenticationLayout: Bool {
        #if os(macOS)
        route.isAuthentication && route != .firstAgent
        #else
        route.isAuthentication
        #endif
    }
    @ViewBuilder private func page(height: CGFloat) -> some View {
        if route == .browser { WorkspaceBrowserDestination() }
        else if route == .file && store.mode == .live { WorkspaceLocalFileView() }
        else if route == .search && store.mode == .live { WorkspaceLocalSearchView() }
        else {
        #if os(macOS)
        if [.createAgent, .editAgent, .firstAgent].contains(route) { MacAgentCreationView(isEditing: route == .editAgent) }
        else if route == .marketplace { MacMarketplacePage() }
        else if [.home, .chat, .newChat].contains(route) { MacWorkspaceChatPage(route: route) }
        else { scrollingPage(height: height) }
        #else
        scrollingPage(height: height)
        #endif
        }
    }
    private func scrollingPage(height: CGFloat) -> some View {
        scrollingContent(height: height)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition(store.navigation.position(for: route))
        .onAppear { store.navigation.restorePosition(for: route) }
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { old, new in
            if abs(old - new) > 0.5 { store.navigation.recordOffset(new, for: route) }
        }
        #endif
    }
    @ViewBuilder private func scrollingContent(height: CGFloat) -> some View {
        #if os(iOS)
        if PhoneWorkspacePageHeader.isUsed(on: route) { PhonePage { content } }
        else { legacyScrollingContent(height: height) }
        #else
        legacyScrollingContent(height: height)
        #endif
    }
    private func legacyScrollingContent(height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .padding(pagePadding)
                #if os(iOS)
                .padding(.bottom, PhoneTabBar.isVisible(on: route) ? 80 : 24)
                #endif
                .frame(minHeight: route == .home ? max(0, height - 1) : nil, alignment: .top)
                .frame(maxWidth: WorkspaceStyle.contentWidth).frame(maxWidth: .infinity, alignment: .top)
        }
    }
    private var pagePadding: CGFloat {
        #if os(macOS)
        28
        #else
        20
        #endif
    }
    @ViewBuilder private var content: some View {
        switch route {
        case .skills: WorkspaceSkillsView()
        case .agents, .agentProfile, .createAgent, .editAgent, .files, .schedules, .createSchedule: WorkspaceTeamView(route: route)
        case .settings, .settingsProfile, .settingsStorage, .settingsUpdates, .appSettings, .account, .models, .permissions, .connections, .devices, .pair, .memory, .mcp, .browserSettings, .permissionRules, .appearance, .language, .notifications: WorkspaceSettingsView(route: route)
        default: WorkspaceTaskView(route: route)
        }
    }
}

struct WorkspaceRootView: View {
    @State var store: WorkspaceStore
    #if os(macOS)
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .light
    #else
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .system
    #endif
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            #if os(macOS)
            if store.isRestoringSession {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(store.t("Loading…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minWidth: MacWorkspaceLayout.minimumWidth, minHeight: MacWorkspaceLayout.minimumHeight)
                    .accessibilityIdentifier("workspace.restoring-session")
            } else {
                desktop
            }
            #else
            phone
            #endif
        }
        .modifier(WorkspaceBrowserHost())
        .environment(store)
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            store.languagePreferences.refreshSystemLanguage()
        }
        .environment(\.locale, Locale(identifier: store.language == "ru" ? "ru_RU" : "en_GB"))
        .environment(\.timeZone, store.mode == .preview ? TimeZone(identifier: "Asia/Yekaterinburg")! : .current)
        .background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink)
        .blotTheme(effectiveTheme)
        .tint(WorkspaceStyle.ink)
        .kMotionRoot(reduceMotion: reduceMotion)
        .sheet(isPresented: $store.catalogVisible) { WorkspaceCatalogView().environment(store) }
        .sheet(isPresented: $store.groupCreationVisible, onDismiss: { store.groupEditingID = nil }) {
            WorkspaceGroupEditor(conversation: store.snapshot.conversations.first { $0.metadata.id == store.groupEditingID },
                participants: store.snapshot.participants ?? []).environment(store)
        }
        .sheet(isPresented: $store.conflictsVisible) { WorkspaceConflictsView().environment(store) }
        .task { await store.loadWorkspace() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.synchronizeAccount()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, store.mode == .live else { return }
            store.languagePreferences.refreshSystemLanguage()
            await store.enqueueDueSchedules()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.updateChatVisibility(nil, atLatest: false); store.persistChatState(immediately: true) }
        }
        .onDisappear { store.persistChatState(immediately: true) }
        .modifier(AppleInteractionHost(center: store.appleIntegrations?.interactions))
        .onOpenURL { url in
            #if os(iOS)
            if store.handleWidgetURL(url) { return }
            #endif
            if ["blot-agent-ios", "blot-agent-macos"].contains(url.scheme ?? ""), url.host == "apple-connections" {
                #if os(macOS)
                store.navigate(.marketplace)
                #else
                store.pluginCatalogVisible = true
                #endif
            } else if store.appleIntegrations?.interactions.handle(url) != true { store.handleBrowserLaunch(url) }
        }
        #if os(macOS)
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #endif
        #if os(iOS)
        .onChange(of: scenePhase) { _, _ in store.publishWidgets(immediately: true) }
        .onChange(of: store.language) { _, _ in store.publishWidgets() }
        #endif
        .confirmationDialog(store.t("Delete chat?"), isPresented: Binding(
            get: { store.pendingChatDeletionID != nil },
            set: { if !$0 { store.pendingChatDeletionID = nil } }), titleVisibility: .visible,
            presenting: store.pendingChatDeletionID) { id in
                Button(store.t("Delete chat"), role: .destructive) { store.deleteChat(id) }.disabled(store.busy)
                Button(store.t("Cancel"), role: .cancel) { store.pendingChatDeletionID = nil }
        } message: { _ in Text(store.t("The chat history will be deleted. The agent will stay in your team.")) }
        .alert(store.t("Rename chat"), isPresented: Binding(
            get: { store.pendingChatRenameID != nil },
            set: { if !$0 { store.pendingChatRenameID = nil } }), presenting: store.pendingChatRenameID) { id in
                TextField(store.t("Chat name"), text: $store.chatTitleDraft)
                Button(store.t("Save")) { store.renameChat(id) }
                    .disabled(store.chatTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(store.t("Cancel"), role: .cancel) { store.pendingChatRenameID = nil }
        }
        #if os(macOS)
        .modifier(MacAdaptiveSheetHost())
        #endif
    }
    private var effectiveTheme: ThemePreference {
        #if os(macOS)
        !store.isRestoringSession && store.route.isAuthentication && store.route != .firstAgent ? .dark : theme
        #else
        theme
        #endif
    }
    #if os(macOS)
    private var desktop: some View {
        Group {
            if store.route.isAuthentication && store.route != .firstAgent { WorkspacePage(route: store.route) }
            else { MacWorkspaceShell() }
        }.frame(minWidth: MacWorkspaceLayout.minimumWidth, minHeight: MacWorkspaceLayout.minimumHeight)
            .overlay {
                if store.mode == .preview && !ProcessInfo.processInfo.arguments.contains("--team-design") && store.route.isSetting {
                    Color.black.opacity(0.25)
                    WorkspaceSettingsPanel(route: store.route)
                        .frame(maxWidth: 860, maxHeight: 640)
                        .clipShape(RoundedRectangle(cornerRadius: BlotRadius.panel)).padding(28)
                }
            }
            .sheet(item: Binding(
                get: { store.mode == .preview && !ProcessInfo.processInfo.arguments.contains("--team-design") ? store.settingsRoute : nil },
                set: { store.settingsRoute = $0 }
            )) { route in
                WorkspaceSettingsPanel(route: route).frame(width: 860, height: 640).environment(store)
            }
    }
    #else
    private var phone: some View {
        PhoneWorkspaceNavigationStack()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.rootRoute.isAuthentication && !store.pluginCatalogVisible && PhoneTabBar.isVisible(on: store.route) {
                PhoneTabBar().offset(y: 8)
            }
        }
        .sheet(isPresented: $store.searchVisible) {
            PhoneSearchView().environment(store)
                .presentationDetents([.medium, .large]).presentationCornerRadius(32)
                .presentationDragIndicator(.visible)
        }
        .task(id: store.providerAvatarRequest) {
            if let request = store.providerAvatarRequest { await store.importProviderAvatar(request) }
        }
        .sheet(isPresented: $store.agentPickerVisible) {
            PhoneChatAgentPicker().environment(store)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $store.agentAppearanceVisible) {
            PhoneAgentCreationView(isEditing: true).environment(store)
                .presentationDetents([.large]).presentationCornerRadius(40)
        }
        .sheet(item: $store.authenticationSession) { session in
            PhoneAuthenticationView(initialRoute: session.route)
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(40)
                .presentationBackground(PhoneReferenceStyle.authentication)
        }
        .sheet(isPresented: $store.agentCreationVisible) {
            PhoneAgentCreationView().environment(store)
                .presentationDetents([.large]).presentationCornerRadius(40)
                .presentationDragIndicator(.hidden).presentationBackground(WorkspaceStyle.surface)
        }
        .sheet(isPresented: $store.pluginCatalogVisible) {
            PhonePluginsView().environment(store)
                .presentationDetents([.large]).presentationCornerRadius(32)
                .presentationDragIndicator(.hidden)
        }
        .sensoryFeedback(.selection, trigger: store.agentCreationVisible)
        .sensoryFeedback(.selection, trigger: store.authenticationRoute)
        .sensoryFeedback(.selection, trigger: store.pluginCatalogVisible)
        .sensoryFeedback(.selection, trigger: store.pinnedConversationIDs)
        .sensoryFeedback(.selection, trigger: store.chatInteractions.messages)
        .sensoryFeedback(.success, trigger: store.snapshot.agents.count) { old, new in new > old }
        .sensoryFeedback(.selection, trigger: store.route) { _, destination in
            guard !PhoneTabBar.isTab(destination) else { return false }
            #if DEBUG
            store.navigation.recordRouteFeedback(destination)
            #endif
            return true
        }
        .sensoryFeedback(.success, trigger: store.snapshot.messages.last?.metadata.id) { _, _ in
            store.snapshot.messages.last?.role == .user
        }
        .sensoryFeedback(.error, trigger: store.error) { _, error in error != nil }
    }

    #endif
}

struct WorkspaceCatalogView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var preview: WorkspaceStore?
    var body: some View {
        NavigationStack {
            List {
                Section(store.t("Preview data · no external actions")) {
                    ForEach(WorkspaceReference.all.filter {
                        #if os(macOS)
                        $0.platform == .desktop
                        #else
                        $0.platform == .ios
                        #endif
                    }) { reference in
                        Button(reference.file) { preview = WorkspaceStore(mode: .preview, route: reference.route) }
                    }
                }
            }.navigationTitle(store.t("Screen catalog"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Close")) { store.catalogVisible = false } } }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview {
                VStack(spacing: 0) {
                    HStack {
                        Text(store.t("Preview data · no external actions")).font(.caption)
                        Spacer()
                        Picker(store.t("State"), selection: Binding(get: { preview.screenState }, set: { preview.screenState = $0 })) {
                            ForEach(WorkspaceStore.ScreenState.allCases, id: \.self) { Text(store.t($0.rawValue)).tag($0) }
                        }.fixedSize()
                        Button(store.t("Close")) { self.preview = nil }
                    }.padding(12)
                    WorkspaceRootView(store: preview)
                }
            }
        }
    }
}

@MainActor
enum WorkspaceBootstrap {
    static func makeStore() -> WorkspaceStore {
        #if DEBUG
        #if os(macOS)
        if ProcessInfo.processInfo.arguments.contains("--team-design") {
            let store = WorkspaceStore(mode: .preview, route: .chat)
            store.language = "ru"
            return store
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--workspace-preview") {
            let arguments = ProcessInfo.processInfo.arguments
            let screen = arguments.firstIndex(of: "--screen").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            let reference = WorkspaceReference.all.first { $0.file == screen }
            let store = WorkspaceStore(mode: .preview, route: reference?.route ?? .home)
            if arguments.contains("--ru") { store.language = "ru" }
            return store
        }
        #endif
        do {
            let configuration = try AppleInstallationConfiguration.load()
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("Blot/AccountsV3", isDirectory: true)
            let service = try WorkspaceAccountApplicationService(installation: configuration, directory: directory)
            return WorkspaceStore(mode: .live, service: service)
        } catch {
            let store = WorkspaceStore(mode: .live)
            store.error = "Сервис подтверждения почты не настроен. Локальная синхронизация не требует облачного relay."
            return store
        }
    }
}
