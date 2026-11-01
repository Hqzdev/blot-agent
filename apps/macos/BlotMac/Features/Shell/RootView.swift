import BlotAPI
import BlotDesign
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @Namespace private var blotNamespace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reducedMotion: Bool { systemReduceMotion || state.settings.reduceMotion }
    var body: some View {
        Group {
            if state.isSignedIn { workspace.disabled(state.isSigningOut) }
            else { LoginView() }
        }
        .background(K.bg)
        .environment(\.blotNamespace, blotNamespace)
        .environment(\.blotReduceMotion, reducedMotion)
        .transaction { transaction in
            if reducedMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
        .onExitCommand { state.handleEscape() }
        .overlay { ToastHost(center: state.toasts) }
        .overlay {
            if state.isSignedIn && state.paletteVisible {
                CommandPaletteView().transition(.opacity)
            }
        }
        .animation(reducedMotion ? nil : KMotion.quick, value: state.paletteVisible)
        .onChange(of: state.paletteVisible) { _, visible in if visible { KMenuController.shared.close() } }
        .onAppear {
            state.shell.history.record(state.shellDestination)
        }
        .task(id: state.currentUser?.email) {
            await state.workspaceLibrary.restoreAccount(state.currentUser?.email)
        }
        .task(id: (state.currentUser?.accountID?.uuidString ?? "") + BackendRuntime.shared.client.baseURL.absoluteString) {
            guard let ownerID = state.currentUser?.accountID else { return }
            await state.workspace.observe(client: BackendRuntime.shared.client, ownerID: ownerID)
        }
        .onChange(of: state.shellDestination) { _, destination in state.shell.history.record(destination) }
        .onChange(of: state.shellProjectID) { _, _ in state.shell.previewSource = nil }
    }
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { state.sidebarVisible ? .all : .detailOnly },
                set: { state.sidebarVisible = $0 != .detailOnly })
    }

    private var workspace: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            Group {
                if state.showingSettings { SettingsSidebar() }
                else { Sidebar() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(K.bgSidebar.ignoresSafeArea())
            .navigationSplitViewColumnWidth(min: K.projectSidebarMin, ideal: K.sidebarWidth, max: K.projectSidebarMax)
        } detail: {
            VStack(spacing: 0) {
                WorkspaceStatusView()
                HStack(spacing: 0) {
                    main.id(mainIdentity).frame(maxWidth: .infinity, maxHeight: .infinity)
                    if state.shellPanelVisible {
                        VDivider()
                        ShellRightPane()
                            .frame(width: state.shellRightExpanded ? 480 : K.projectPanelWidth)
                            .background(K.bgSidebar)
                    }
                }
            }
            .background(K.bg)
            .navigationTitle(state.isNewConversation && state.workChat.selectedProjectID == nil ? "Blot" : state.shellTitle)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { ShellToolbar() }
        .confirmationDialog("Остановить запуск?", isPresented: Binding(get: { state.confirmingStopRun },
                                                                       set: { state.confirmingStopRun = $0 })) {
            Button("Остановить", role: .destructive) { state.stopCurrentWorkRun() }
            Button("Продолжить работу", role: .cancel) {}
        } message: {
            Text("Команда завершит работу. Уже сделанные изменения сохранятся в результатах.")
        }
        .onChange(of: state.workspace.cursor) { _, _ in
            state.workChat.updateProjects(state.workspace.rows("PROJECT"))
        }
    }
    /// Changes when the user moves to another section, so the main area cross-fades between screens.
    private var mainIdentity: String {
        if state.showingSettings { return "settings" }
        if state.profileVisible { return "profile" }
        if let tool = state.activeTool { return "tool:" + tool.rawValue }
        return state.product == .code ? "code:\(state.codeRoute):\(state.teamRoute)" : "work:\(state.workRoute)"
    }
    @ViewBuilder private var main: some View {
        if state.showingSettings { SettingsView() }
        else if state.profileVisible { ProfilePageView() }
        else if let tool = state.activeTool { WorkspaceToolsView(tool: tool) }
        else {
            switch state.product {
            case .code:
                switch state.codeRoute {
                case .home: HomeView()
                case .blot: BlotMotionPreview()
                case .motes:
                    switch state.teamRoute {
                    case .newRun: NewRunView()
                    case .chat: TeamChatView()
                    case .graph: TeamGraphView()
                    }
                case .automations: AutomationsView()
                case .skills: SkillsView()
                case let .task(projectID, taskID):
                    if let task = state.task(projectID: projectID, taskID: taskID) { TaskChatView(projectID: projectID, task: task) }
                    else { EmptyState(icon: "message-square", title: "Task not found", detail: "It may have been removed. Choose another task in the sidebar.") }
                }
            case .work:
                switch state.workRoute {
                case .home, .chat: WorkChatView()
                case .automations: AutomationsView()
                case .skills: SkillsView()
                case .blot: BlotMotionPreview()
                }
            }
        }
    }
}
