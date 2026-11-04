import BlotDesign
import SwiftUI

/// Fixtures compose production views; no authentication, file or network actions run.
@MainActor
struct MacRenderScenario {
    let name: String
    let auth: AuthScreen?
    let configure: (AppState) -> Void
    let overlay: (AppState) -> AnyView?

    init(_ name: String, auth: AuthScreen? = nil,
         configure: @escaping (AppState) -> Void = { _ in },
         overlay: @escaping (AppState) -> AnyView? = { _ in nil }) {
        self.name = name
        self.auth = auth
        self.configure = configure
        self.overlay = overlay
    }

    static let longText = "Проверить все экраны приложения: размеры панелей, перенос длинного текста, поле ввода, меню и клавиатурную навигацию. "

    static var all: [Self] {
        var cases: [Self] = [
            Self("home"),
            Self("home-long", configure: { $0.newTask.draft = String(repeating: longText, count: 6) }),
            Self("home-panel", configure: { $0.toggleShellPanel() }),
            Self("sidebar-wide", configure: { $0.shell.sidebarWidth = 320 }),
            Self("sidebar-hidden", configure: { $0.sidebarVisible = false }),
            Self("chat", configure: completedTask),
            Self("project-card-sources", configure: { state in
                completedTask(state)
                let path = FileManager.default.currentDirectoryPath + "/apps/shared/AppIcon.icon/Assets/Blot.svg"
                let url = URL(fileURLWithPath: path)
                state.shell.addSources([url], projectID: state.shellProjectID)
            }),
            Self("chat-archive", configure: { state in
                completedTask(state)
                state.shell.archive("code:tradr:pnl")
                state.shell.archiveExpanded = true
                if let task = state.projects.first?.tasks.last {
                    state.shell.markUnread("code:" + state.projects[0].id + ":" + task.id)
                }
            }),
            Self("chat-approval", configure: { $0.openTask(projectID: "tradr", taskID: "pnl") }),
            Self("chat-empty", configure: { state in
                completedTask(state); clearTaskThread(state); state.shell.rightVisible = false
            }),
            Self("chat-long", configure: { state in
                completedTask(state); state.codeDraft = String(repeating: longText, count: 6)
            }),
            Self("motes", configure: { $0.openWorkRun("receipt") }),
            Self("motes-empty", configure: { $0.openWorkRun("receipt"); $0.teamChat = [] }),
            Self("work", configure: { $0.openWorkChat() }),
            Self("work-demo-chat", configure: { $0.openWorkChat("work-receipt") }),
            Self("work-project", configure: { $0.openWorkChatProject("java-cart") }),
            Self("mode-picker-code", overlay: { _ in AnyView(ProductModeMenuCard()) }),
            Self("mode-picker-work", configure: { $0.switchProduct(.work) }, overlay: { _ in AnyView(ProductModeMenuCard()) }),
            Self("work-chat", configure: workConversation),
            Self("work-long", configure: { workConversation($0); $0.workChatDraft = String(repeating: longText, count: 6) }),
            Self("scheduled", configure: { $0.openSection(.scheduled) }),
            Self("scheduled-empty", configure: { $0.openSection(.scheduled); $0.automations.items = [] }),
            Self("scheduled-search-empty", configure: { $0.openSection(.scheduled); $0.automations.search = "No matching automation" }),
            Self("scheduled-long", configure: { state in
                state.openSection(.scheduled)
                state.automations.selected?.title = longText
                state.automations.selected?.instructions = String(repeating: longText, count: 8)
            }),
            Self("skills", configure: { $0.openSection(.skills) }),
            Self("skills-empty", configure: { $0.openSection(.skills); $0.skills.items = [] }),
            Self("skills-search-empty", configure: { $0.openSection(.skills); $0.skills.search = "No matching skill" }),
            Self("skills-browse", configure: { $0.openSection(.skills); $0.skills.selectTab(.browse) }),
            Self("skills-team", configure: { $0.openSection(.skills); $0.skills.selectTab(.team) }),
            Self("skills-long", configure: { state in
                state.openSection(.skills)
                state.skills.selected?.title = longText
                state.skills.selected?.summary = String(repeating: longText, count: 3)
            }),
            Self("new-run", configure: { $0.openNewRun() }),
            Self("new-run-long", configure: { $0.openNewRun(); $0.newRun.goal = String(repeating: longText, count: 6) }),
            Self("pet-code", configure: { $0.openPet() }),
            Self("pet-work", configure: { $0.switchProduct(.work); $0.openPet() }),
            Self("skills-work", configure: { $0.switchProduct(.work); $0.openSection(.skills) }),
            Self("scheduled-work", configure: { $0.switchProduct(.work); $0.openSection(.scheduled) }),
            Self("palette", configure: { $0.openCommandPalette() }),
            Self("profile", overlay: { _ in AnyView(ProfileMenuCard { _ in }) }),
            Self("profile-page", configure: { $0.openProfile() }),
            Self("profile-page-stats", configure: { state in
                state.currentUser?.profileStatistics = ProfileStatistics(lifetimeTokens: 45_600_000_000, peakTokens: 1_100_000_000,
                                                                        longestTaskSeconds: 51_180, longestStreakDays: 143, currentStreakDays: 143)
                state.openProfile()
            }),
            Self("profile-page-long", configure: { state in
                state.currentUser?.name = String(repeating: "Yaroslav Fairfield ", count: 4)
                state.openProfile()
            }),
            Self("profile-edit", configure: { $0.openProfile() }, overlay: { AnyView(ProfileEditorView(details: $0.profileDetails) { _ in }) }),
            Self("profile-showcase", configure: { $0.openProfile() }, overlay: { _ in
                AnyView(ProfileShowcaseView(sites: [SavedSite(id: UUID(), name: "Example site", url: URL(string: "https://example.com")!)]) { }
                    .padding(24).frame(width: 600))
            }),
            Self("profile-help", overlay: { _ in AnyView(ProfileMenuCard(showingHelp: true) { _ in }) }),
            Self("sign-up", auth: .signUp),
            Self("log-in", auth: .logIn),
            Self("verify-email", auth: .verify),
            Self("skill-create", configure: { $0.openSection(.skills) }, overlay: { _ in AnyView(SkillEditorView { _ in }) }),
            Self("skill-edit", configure: { $0.openSection(.skills) }, overlay: { AnyView(SkillEditorView(item: $0.skills.selected) { _ in }) }),
            Self("automation-create", configure: { $0.openSection(.scheduled) }, overlay: { _ in AnyView(AutomationEditorView { _ in }) }),
            Self("automation-edit", configure: { $0.openSection(.scheduled) }, overlay: { AnyView(AutomationEditorView(item: $0.automations.selected) { _ in }) }),
            Self("api-key", configure: { $0.showingSettings = true; $0.settings.section = .models }, overlay: { _ in AnyView(APIKeyPreviewSheet()) }),
            Self("usage", configure: { $0.showingSettings = true; $0.settings.section = .billing }, overlay: { _ in AnyView(UsagePreviewView()) }),
            Self("model-effort", overlay: { _ in AnyView(modelPanel(choosing: false)) }),
            Self("model-list", overlay: { _ in AnyView(modelPanel(choosing: true)) }),
            Self("settings-from-chat", configure: { completedTask($0); $0.showingSettings = true }),
            Self("settings-wide", configure: { $0.showingSettings = true; $0.shell.sidebarWidth = 320 }),
            Self("settings-search-empty", configure: { $0.showingSettings = true; $0.settings.search = "No matching setting" })
        ]
        cases.append(Self("workspace-menu", overlay: { _ in AnyView(WorkspaceMoreMenuCard()) }))
        cases.append(Self("loading-blocks", overlay: { _ in AnyView(ContentSkeleton().frame(width: 600, height: 500)) }))
        cases.append(Self("loading-sidebar", overlay: { _ in AnyView(SidebarSkeleton().frame(width: K.sidebarWidth, height: 480)) }))
        cases.append(Self("loading-startup"))
        for tool in WorkspaceTool.allCases {
            cases.append(Self("workspace-" + tool.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"),
                              configure: { $0.openTool(tool) }))
        }
        cases.append(Self("task-missing", configure: { $0.codeRoute = .task(projectID: "tradr", taskID: "missing") }))
        cases.append(Self("source-diff", configure: { state in
            completedTask(state)
            state.shell.previewSource = ProjectSource(id: "preview-diff", name: "fees.ts", path: "src/lib/fees.ts")
        }))
        cases.append(Self("source-unavailable", configure: { state in
            completedTask(state)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            state.shell.previewSource = ProjectSource(id: "preview-unavailable", name: "Unavailable file", path: url.path, url: url)
        }))
        for taskID in ["onboarding", "csv"] {
            cases.append(Self("review-" + taskID, configure: { state in
                state.openTask(projectID: "tradr", taskID: taskID)
                state.approve(projectID: "tradr", taskID: taskID)
                if let task = state.currentTask {
                    state.openReview(projectID: "tradr", task: task)
                    state.reviewSession(projectID: "tradr", taskID: taskID)?.tab = .preview
                }
            }))
        }
        for tab in ReviewTab.allCases {
            let name = tab == .changes ? "review" : "review-" + tab.rawValue.lowercased()
            cases.append(Self(name, configure: { state in
                completedTask(state)
                guard let task = state.currentTask else { return }
                state.openReview(projectID: "tradr", task: task)
                state.reviewSession(projectID: "tradr", taskID: task.id)?.tab = tab
            }))
        }
        cases.append(Self("review-empty", configure: { state in
            completedTask(state); clearTaskThread(state)
            if let task = state.currentTask { state.openReview(projectID: "tradr", task: task) }
        }))
        cases.append(Self("review-discarded", configure: { state in
            completedTask(state)
            if let task = state.currentTask {
                state.openReview(projectID: "tradr", task: task)
                state.reviewSession(projectID: "tradr", taskID: task.id)?.outcome = .discarded
            }
        }))
        for mode in GraphMode.allCases {
            let name = mode == .communication ? "graph" : "graph-" + String(describing: mode)
            cases.append(Self(name, configure: { $0.openGraph(selecting: .nativeFrontend); $0.graphMode = mode }))
        }
        for section in SettingsSection.allCases {
            let name = section == .general ? "settings" : "settings-" + String(describing: section)
            cases.append(Self(name, configure: { $0.showingSettings = true; $0.settings.section = section }))
        }
        for sheet in [ProfileSheet.invitation, .guide, .about] {
            cases.append(Self("profile-" + sheet.rawValue, overlay: { _ in AnyView(ProfileSheetView(sheet: sheet)) }))
        }
        for (name, title, label, value) in [
            ("folder-edit", "Projects folder", "Folder path", "~/Developer/blot"),
            ("command-add", "Add allowed command", "Command", ""),
            ("server-add", "Add MCP server", "Server name", "")
        ] {
            cases.append(Self(name, configure: { $0.showingSettings = true }, overlay: { _ in
                AnyView(SettingsEditSheet(title: title, label: label, initialValue: value) { _ in })
            }))
        }
        return cases
    }

    private static func completedTask(_ state: AppState) {
        state.openTask(projectID: "tradr", taskID: "pnl")
        state.approve(projectID: "tradr", taskID: "pnl")
    }

    private static func clearTaskThread(_ state: AppState) {
        guard let project = state.projects.firstIndex(where: { $0.id == "tradr" }),
              let task = state.projects[project].tasks.firstIndex(where: { $0.id == "pnl" }) else { return }
        state.projects[project].tasks[task].thread = []
    }

    private static func workConversation(_ state: AppState) {
        state.openWorkChat()
        state.workChatDraft = "Помоги составить план на неделю"
        state.sendWorkChatMessage()
    }

    private static func modelPanel(choosing: Bool) -> ModelPickerPanel {
        ModelPickerPanel(options: ModelOption.options(from: ["Blot 1", "Blot 1 Mini"]),
                         selectedModel: .constant(""), effort: .constant(.high),
                         defaultModel: "Blot 1", choosingModel: choosing)
    }
}

struct MacRenderPreview: View {
    let scenario: MacRenderScenario
    let state: AppState
    let login: LoginViewModel?

    var body: some View {
        Group {
            if let login {
                LoginView(model: login).background(WindowChrome().frame(width: 0, height: 0))
            } else {
                BlotWindowContent(state: state)
            }
        }
        .overlay(alignment: scenario.name.hasPrefix("profile") && !["profile-invitation", "profile-guide", "profile-about"].contains(scenario.name) ? .bottomLeading : .center) {
            if let overlay = scenario.overlay(state) {
                if scenario.name == "profile" || scenario.name == "profile-help" {
                    overlay.padding(.leading, 50).padding(.bottom, 4)
                } else {
                    ZStack {
                        K.scrim
                        overlay.kCard(radius: 16, fill: K.bg, stroke: K.borderStrong)
                    }
                }
            }
        }
        .environment(state)
        .blotTheme(state.theme).tint(K.inverse)
        .environment(\.scenePhase, .inactive)
    }
}
