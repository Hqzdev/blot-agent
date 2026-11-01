import BlotAPI
import Observation
import BlotDesign
import SwiftUI

enum Product: String {
    case code = "Code"
    case work = "Work"

    var subtitle: String {
        switch self {
        case .code: "Build, debug, and ship"
        case .work: "Create, learn, and explore"
        }
    }
}

enum CodeRoute: Hashable {
    case home
    case task(projectID: String, taskID: String)
    case automations
    case skills
    case blot
    case motes
}

enum TeamRoute: Hashable {
    case newRun
    case chat(runID: String)
    case graph
}

enum WorkRoute: Hashable {
    case home
    case chat(id: String)
    case automations
    case skills
    case blot
}

enum GraphMode: String, CaseIterable, Identifiable {
    case organization = "Organization"
    case communication = "Communication & work"
    case dependencies = "Dependencies"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .organization: "point.3.connected.trianglepath.dotted"
        case .communication: "bubble.left.and.bubble.right"
        case .dependencies: "arrow.triangle.branch"
        }
    }
}

/// What the graph inspector shows.
enum GraphSelection: Hashable {
    case edge(String)
    case node(String)
}

// Состояние навигации. Данные работы принадлежат LiveWorkspace и приходят с сервера.
@MainActor
@Observable
final class AppState {
    var currentUser: AuthUser?
    var isSignedIn: Bool { currentUser != nil }
    private(set) var isSigningOut = false
    let workspace = LiveWorkspace(client: { BackendRuntime.shared.client })
    let workChat = WorkChatState()
    var product: Product = .work
    var codeRoute: CodeRoute = .home
    var workRoute: WorkRoute = .home
    var teamRoute: TeamRoute = .newRun
    var sidebarVisible = true
    /// Loaded from this Mac's defaults; `chooseTheme` saves a new choice. Previews and render
    /// checks may set `theme` directly without touching the stored preference.
    var theme: ThemePreference = ThemeStore.load()
    let shell = ShellState()
    var activeTool: WorkspaceTool?
    var profileVisible = false
    let workspaceLibrary = WorkspaceLibrary()
    let pluginUsage = AccountPluginUsage()
    let settings = SettingsState()
    let toasts = ToastCenter()
    var showingSettings = false
    var showDevicePairing = false
    var paletteVisible = false
    /// Stop run asks first: a stopped run cannot be resumed.
    var confirmingStopRun = false
    let newTask = NewTaskState()
    let newRun = NewRunState()
    let skills = LibrarySelection()
    let automations = LibrarySelection()
    var reviewVisible = false
    var blotStimulus = BlotStimulus()
    var expandedProjectID: String?
    var showAllTasks = false
    var selectedRunID = ""
    var graphMode: GraphMode = .communication
    var graphSelection: GraphSelection?
    var inspectorVisible = false
    var liveSeq: Int { Int(clamping: workspace.cursor) }

    func chooseTheme(_ preference: ThemePreference) {
        theme = preference
        ThemeStore.save(preference)
    }

    func pokeBlot(_ kind: BlotStimulusKind, context: BlotContext? = nil) {
        blotStimulus = BlotStimulus(
            kind: kind, id: blotStimulus.id + 1,
            context: context ?? activeBlotContext, createdAt: Date())
    }
    func react(_ reaction: BlotState, context: BlotContext? = nil) {
        switch reaction {
        case .happy, .wink: pokeBlot(.success, context: context)
        case .error: pokeBlot(.failure, context: context)
        case .jump: pokeBlot(.sent, context: context)
        default: pokeBlot(.none, context: context)
        }
    }
    func restoreBackendSession() async {
        do {
            try await BackendRuntime.shared.start()
            if let user = try await LiveAuthService().restore() { signIn(user, remember: true) }
        } catch { /* Экран входа показывает ошибку соединения. */  }
    }
    func signIn(_ user: AuthUser, remember: Bool) {
        workspace.clear()
        skills.clear()
        automations.clear()
        shell.clearAccount()
        workChat.clear()
        workRoute = .home
        product = .work
        if let accountID = user.accountID { workspace.selectAccount(accountID) }
        workspace.beginCommandRecovery()
        workspaceLibrary.selectAccount(user.email)
        SessionStore.rememberEmail(user.email)
        if remember { SessionStore.save(user) } else { SessionStore.clear() }
        codeRoute = .home
        teamRoute = .newRun
        selectedRunID = ""
        newTask.projectID = ""
        newRun.projectID = ""
        withAnimation(KMotion.panel) { currentUser = user }
        Task {
            await recoverWorkspaceCommands()
            guard currentUser?.accountID == user.accountID else { return }
            try? await workChat.load()
        }
    }
    func recoverWorkspaceCommands() async {
        guard let accountID = currentUser?.accountID else { return }
        workspace.beginCommandRecovery()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                "Blot/pending/" + (BackendRuntime.shared.installationId ?? "local") + "/"
                    + accountID.uuidString)
        do {
            try await BackendRuntime.shared.client.persistPendingCommands(in: directory)
            guard currentUser?.accountID == accountID else { return }
            await workspace.recoverPendingCommands()
        } catch {
            guard currentUser?.accountID == accountID else { return }
            workspace.commandRecoveryFailed(error.localizedDescription)
        }
    }
    func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        let client = BackendRuntime.shared.client
        Task {
            let _: [String: Bool]? = try? await client.post(
                "v2/auth/logout", body: [String: String](), as: [String: Bool].self)
            await client.useToken(nil)
            isSigningOut = false
            withAnimation(KMotion.panel) { currentUser = nil }
        }
        workspace.clear()
        skills.clear()
        automations.clear()
        workChat.clear()
        shell.clearAccount()
        newTask.draft = ""
        newRun.goal = ""
        profileVisible = false
        activeTool = nil
        workspaceLibrary.selectAccount(nil)
        SessionStore.clear()
        paletteVisible = false
        showingSettings = false
    }

    func openNewItem() {
        if product == .work { openWorkChat() } else if isMotes { openNewRun() } else { openHome() }
    }
    func openNewRun() {
        resetPanels()
        product = .code
        codeRoute = .motes
        teamRoute = .newRun
    }
    func openWorkRun(_ id: String) {
        guard workspace.find("RUN", id) != nil else { return }
        resetPanels()
        shell.markRead("motes:" + id)
        selectedRunID = id
        product = .code
        codeRoute = .motes
        teamRoute = .chat(runID: id)
        graphSelection = nil
    }
    func openHome(draft: String? = nil) {
        resetPanels()
        product = .code
        codeRoute = .home
        expandedProjectID = newTask.projectID
        if let draft { newTask.draft = draft }
    }
    func openTask(projectID: String, taskID: String) {
        guard workspace.find("RUN", taskID)?.projectId?.uuidString == projectID else { return }
        resetPanels()
        shell.markRead("code:" + projectID + ":" + taskID)
        product = .code
        expandedProjectID = projectID
        newTask.projectID = projectID
        selectedRunID = taskID
        codeRoute = .task(projectID: projectID, taskID: taskID)
        shell.lastCodeChat = codeRoute
    }
    func switchProduct(_ product: Product) {
        resetPanels()
        self.product = product
    }
    func toggleProject(_ id: String) {
        withAnimation(KMotion.standard) { expandedProjectID = expandedProjectID == id ? nil : id }
    }
    func openGraph() {
        resetPanels()
        product = .code
        codeRoute = .motes
        teamRoute = .graph
    }
    func openCommandPalette() { if isSignedIn { paletteVisible = true } }
    private func resetPanels() {
        profileVisible = false
        activeTool = nil
        showingSettings = false
        paletteVisible = false
        shell.previewSource = nil
        reviewVisible = false
        inspectorVisible = false
    }
    func handleEscape() {
        if paletteVisible { paletteVisible = false }
    }
    func openReview(projectID: String, task: TaskItem) {
        selectedRunID = task.id
        reviewVisible = true
        shell.rightVisible = true
        shell.previewSource = nil
    }
    func stopCurrentWorkRun() { controlCurrentRun("run.stop") }
    func pauseOrResumeRun() {
        guard let run = workspace.find("RUN", selectedRunID) else { return }
        controlCurrentRun(
            ["PAUSED", "WAITING", "INTERRUPTED"].contains(run.data.text("status"))
                ? "run.resume" : "run.pause")
    }
    private func controlCurrentRun(_ type: String) {
        guard let run = workspace.find("RUN", selectedRunID) else { return }
        let verb = switch type {
        case "run.stop": "stop"
        case "run.pause": "pause"
        default: "resume"
        }
        Task {
            do {
                try await workspace.send(type, payload: .object(["id": .string(run.id.uuidString)]), row: run)
            } catch {
                toasts.show("Couldn't \(verb) the run. \(error.localizedDescription)", tone: .error)
            }
        }
    }
}
