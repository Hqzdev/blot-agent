import BlotDesign
import BlotAPI
import Foundation

extension AppState {
    var shellSidebarVisible: Bool {
        sidebarVisible
    }

    var shellPanelVisible: Bool {
        activeTool == nil && shell.rightVisible && shellSupportsProjectPanel &&
            (product != .code || codeRoute != .home || shell.homePanelVisible)
    }
    func toggleShellPanel() {
        if product == .code && codeRoute == .home {
            shell.homePanelVisible = !shellPanelVisible
            if shell.homePanelVisible { shell.rightVisible = true }
        } else {
            shell.rightVisible.toggle()
        }
        if !shellPanelVisible {
            reviewVisible = false; shell.previewSource = nil; inspectorVisible = false
        }
    }
    var shellDestination: ShellDestination {
        ShellDestination(tool: activeTool, profile: profileVisible, product: product, code: codeRoute, work: workRoute, team: teamRoute, runID: selectedRunID,
                         settings: showingSettings, settingsSection: settings.section,
                         homeProjectID: newTask.projectID, workProjectID: workChat.selectedProjectID, runProjectID: newRun.projectID)
    }
    func navigateHistory(_ offset: Int) {
        guard let destination = shell.history.move(offset) else { return }
        activeTool = destination.tool
        profileVisible = destination.profile
        product = destination.product
        codeRoute = destination.code
        workRoute = destination.work
        teamRoute = destination.team
        if product == .work, case let .chat(id) = workRoute { shell.markRead("chat:" + id) }
        if product == .code, case let .task(project, task) = codeRoute { shell.markRead("code:" + project + ":" + task) }
        if product == .code, codeRoute == .motes, teamRoute != .newRun { shell.markRead("motes:" + destination.runID) }
        if product == .code, case .task = codeRoute { shell.lastCodeChat = codeRoute }
        if product == .work, case .chat = workRoute { shell.lastWorkChat = workRoute }
        selectedRunID = destination.runID
        showingSettings = destination.settings
        settings.section = destination.settingsSection
        newTask.projectID = destination.homeProjectID
        workChat.selectProject(destination.workProjectID)
        newRun.projectID = destination.runProjectID
        paletteVisible = false
        reviewVisible = false
        shell.previewSource = nil
        inspectorVisible = false
        if case let .task(projectID, _) = codeRoute { expandedProjectID = projectID; newTask.projectID = projectID }
        else { expandedProjectID = newTask.projectID }
    }
    var shellTitle: String {
        if showingSettings { return settings.section.rawValue }
        if profileVisible { return "Profile" }
        if let activeTool { return activeTool.rawValue }
        if product == .code {
            switch codeRoute {
            case .home: return "New task"
            case .task: return currentTask?.title ?? "Task"
            case .automations: return "Scheduled"
            case .skills: return "Skills"
            case .blot: return "Blot"
            case .motes:
                switch teamRoute {
                case .newRun: return "New Motes run"
                case .chat: return currentWorkSession?.title ?? "Motes"
                case .graph: return "Motes graph · " + (currentWorkSession?.title ?? "Code")
                }
            }
        }
        switch workRoute {
        case .home: return workChat.selectedProject?.name ?? "Новый чат"
        case .chat: return currentWorkChat?.title ?? "Chat"
        case .blot: return "Blot"
        case .automations: return "Scheduled"
        case .skills: return "Skills"
        }
    }
    var shellProjectID: String {
        if isMotes { return teamRoute == .newRun ? newRun.projectID : (currentWorkSession?.projectID ?? newRun.projectID) }
        if product == .code {
            if case let .task(projectID, _) = codeRoute { return projectID }
            return codeRoute == .home ? newTask.projectID : (expandedProjectID ?? newTask.projectID)
        }
        return currentWorkChat?.projectID ?? workChat.selectedProjectID ?? ""
    }
    var shellProjectName: String {
        if isMotes { return workProjects.first { $0.id == shellProjectID }?.name ?? shellProjectID }
        if product == .code { return projects.first { $0.id == shellProjectID }?.name ?? shellProjectID }
        return workChat.projects.first { $0.id == shellProjectID }?.name ?? shellProjectID
    }
    var shellRightExpanded: Bool {
        shell.previewSource != nil || (product == .code && reviewVisible && currentTask != nil) ||
            (isMotes && shellHasConversation && inspectorVisible)
    }
    var shellSupportsProjectPanel: Bool {
        guard activeTool == nil, !profileVisible, !showingSettings, product == .code else { return false }
        switch codeRoute { case .home, .task, .motes: return true; default: return false }
    }
    var shellSources: [ProjectSource] {
        var sources = shell.attachedSources[shellProjectID] ?? []
        if product == .code, let project = projects.first(where: { $0.id == shellProjectID }) {
            let tasks = currentTask.map { [$0] } ?? project.tasks
            let paths = tasks.flatMap { task in
                task.thread.flatMap { block -> [String] in
                    switch block {
                    case .changes(let files): return files.map(\.path)
                    case .steps(let steps): return steps.filter { $0.verb == "Read" && $0.target.contains("/") }.map(\.target)
                    default: return []
                    }
                }
            }
            for path in paths where !sources.contains(where: { $0.path == path }) {
                sources.append(ProjectSource(id: shellProjectID + ":" + path,
                                             name: URL(fileURLWithPath: path).lastPathComponent, path: path))
            }
        }
        return sources
    }
    var shellChangedFiles: [ChangedFile] {
        currentTask?.thread.flatMap { block -> [ChangedFile] in
            if case let .changes(files) = block { return files }; return []
        } ?? []
    }
    var shellHasConversation: Bool {
        if isMotes { return teamRoute != .newRun }
        if product == .code { if case .task = codeRoute { return true }; return false }
        return currentWorkChat != nil
    }
    /// Status of the run behind the current task or Motes conversation.
    var currentRunStatus: String? {
        guard isSignedIn, activeTool == nil, !profileVisible, !showingSettings, product == .code else { return nil }
        if case .task = codeRoute, let task = currentTask { return workspace.find("RUN", task.id)?.data.text("status") }
        if isMotes && shellHasConversation { return workspace.find("RUN", selectedRunID)?.data.text("status") }
        return nil
    }
    /// Pause, resume and stop act on the Motes run that is open.
    var runControlsAvailable: Bool {
        isMotes && shellHasConversation && !showingSettings && currentRunStatus != nil
    }
    var currentRunPaused: Bool {
        ["PAUSED", "WAITING", "INTERRUPTED"].contains(currentRunStatus ?? "")
    }
    var canPauseOrResumeRun: Bool {
        runControlsAvailable &&
            ["RUNNING", "PLANNING", "PAUSED", "WAITING", "INTERRUPTED"].contains(currentRunStatus ?? "")
    }
    var canStopRun: Bool {
        guard runControlsAvailable, let status = currentRunStatus, !status.isEmpty else { return false }
        return !BackendStatus(status).isTerminal
    }
    func showShellReview() {
        shell.rightVisible = true
        shell.previewSource = nil
        if product == .code, let task = currentTask { openReview(projectID: shellProjectID, task: task) }
        else if isMotes && shellHasConversation { inspectorVisible = true }
    }
}
