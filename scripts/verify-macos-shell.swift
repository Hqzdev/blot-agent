import AppKit
import BlotDesign
import SwiftUI

/// Standalone checks compiled against the app sources by check-macos-shell.sh.
@main
struct VerifyMacOSShell {
    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        if !CommandLine.arguments.contains("--render-only") {
            try await checkModels()
            checkConversationActions()
            checkConversationMenuActions()
            try await checkWorkspaceLibrary()
        }
        if CommandLine.arguments.contains("--render") || CommandLine.arguments.contains("--render-only") {
            let output = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
            try await renderScreens(to: output)
        }
    }

    @MainActor private static func checkConversationMenuActions() {
        let app = AppState()
        precondition(app.currentConversation == nil)
        app.openTask(projectID: "tradr", taskID: "pnl")
        let source = app.currentConversation!
        let original = app.currentTask!
        let exported = app.transcript(for: source)
        precondition(exported.contains(source.title) && exported.contains("pnl"))
        let fork = app.forkConversation(source)!
        precondition(fork.id != source.id && app.currentTask?.branch == original.branch)
        precondition(app.currentTask?.phase == .stopped && app.currentTask!.thread.count > original.thread.count)
        precondition(app.task(projectID: source.project, taskID: source.taskID)?.phase == original.phase)
        let destination = app.shellDestination
        let side = app.createSideChat(for: fork)
        precondition(app.shellDestination == destination && app.workChat.session(side.id) === side)
        precondition(side.messages.first?.text.contains(fork.title) == true)
        side.send("Independent side chat")
        precondition(app.shellDestination == destination && app.currentTask!.thread.count > original.thread.count)

        app.openWorkChat("work-receipt")
        let chat = app.currentWorkChat!
        let count = chat.messages.count
        let chatFork = app.forkConversation(app.currentConversation!)!
        precondition(chatFork.taskID != chat.id && app.currentWorkChat!.messages.count == count)
        app.currentWorkChat!.send("Independent fork")
        precondition(chat.messages.count == count)

        app.openWorkRun("receipt")
        let run = app.currentWorkSession!
        let status = run.status
        let runFork = app.forkConversation(app.currentConversation!)!
        precondition(runFork.taskID != run.id && app.currentWorkSession!.status == .stopped)
        precondition(!app.currentWorkSession!.approvalPending && app.team.allSatisfy { $0.state == .idle })
        precondition(run.status == status)
        print("PASS: transcript export, stopped forks, isolated Work histories and side chat navigation")
    }

    @MainActor private static func checkConversationActions() {
        let app = AppState()
        let task = SidebarConversation(id: "code:tradr:pnl", title: "Task", project: "tradr", taskID: "pnl", running: true, kind: .task)
        app.openTask(projectID: task.project, taskID: task.taskID)
        let route = app.shellDestination
        let thread = app.currentTask!.thread.count
        app.shell.togglePin(task.id)
        app.shell.archive(task.id)
        precondition(app.shell.archived.contains(task.id) && !app.shell.pins.contains(task.id))
        precondition(app.shellDestination == route && app.currentTask!.thread.count == thread)
        app.shell.togglePin(task.id)
        precondition(!app.shell.pins.contains(task.id))
        app.shell.restore(task.id)
        precondition(!app.shell.archived.contains(task.id) && app.currentTask!.thread.count == thread)
        app.renameConversation(task, to: "  Renamed task  ")
        precondition(app.shellTitle == "Renamed task")
        app.renameConversation(task, to: " \n ")
        precondition(app.shellTitle == "Renamed task")
        app.shell.markUnread(task.id)
        app.openTask(projectID: task.project, taskID: task.taskID)
        precondition(!app.shell.unread.contains(task.id))

        let chat = SidebarConversation(id: "chat:work-receipt", title: "Chat", project: "swift-state", taskID: "work-receipt", running: false, kind: .chat)
        app.openWorkChat(chat.taskID)
        app.workChatDraft = "Keep the draft"
        app.renameConversation(chat, to: "Renamed chat")
        app.shell.archive(chat.id)
        precondition(app.shellTitle == "Renamed chat" && app.workChatDraft == "Keep the draft")
        app.shell.restore(chat.id)
        app.shell.markUnread(chat.id)
        app.openWorkChat(chat.taskID)
        precondition(!app.shell.unread.contains(chat.id) && app.workChatDraft == "Keep the draft")

        let run = SidebarConversation(id: "motes:receipt", title: "Run", project: "swift-state", taskID: "receipt", running: true, kind: .team)
        app.renameConversation(run, to: "Renamed run")
        app.shell.markUnread(run.id)
        app.openWorkRun(run.taskID)
        precondition(app.shellTitle == "Renamed run" && !app.shell.unread.contains(run.id))
        precondition(app.workProjects.first { $0.id == run.project }?.runs.first { $0.id == run.taskID }?.title == "Renamed run")
        print("Conversation actions passed")
    }

    @MainActor private static func checkModels() async throws {
        let app = AppState()
        app.currentUser = AuthUser(email: "preview@blot.local", name: "Preview")
        app.shell.sidebarWidth = 304
        app.openTask(projectID: "tradr", taskID: "pnl")
        precondition(app.shellPanelVisible)
        app.showingSettings = true
        precondition(!app.shellPanelVisible && app.shell.sidebarWidth == 304)
        app.showingSettings = false
        app.openSection(.skills)
        precondition(!app.shellPanelVisible && app.shell.sidebarWidth == 304)
        app.openSection(.scheduled)
        precondition(!app.shellPanelVisible && app.shell.sidebarWidth == 304)
        app.openHome()
        app.shell.sidebarWidth = K.projectSidebarMin
        precondition(!app.shellPanelVisible)
        app.toggleShellPanel(); precondition(app.shellPanelVisible)
        app.toggleShellPanel(); precondition(!app.shellPanelVisible)
        app.newTask.projectID = "knot"
        let home = app.shellDestination
        app.shell.history.record(home)
        app.openTask(projectID: "tradr", taskID: "pnl")
        let task = app.shellDestination
        app.shell.history.record(task)
        app.openWorkRun("receipt")
        let run = app.shellDestination
        app.shell.history.record(run)
        app.navigateHistory(-1)
        precondition(app.shellDestination == task)
        app.shell.history.record(app.shellDestination)
        precondition(app.shell.history.entries.count == 3 && app.shell.history.canGoForward)
        app.navigateHistory(-1)
        precondition(app.shellDestination == home && app.newTask.projectID == "knot" && app.expandedProjectID == "knot")
        app.navigateHistory(1)
        precondition(app.shellDestination == task)
        app.codeRoute = .skills
        app.shell.history.record(app.shellDestination)
        precondition(!app.shell.history.canGoForward && app.shell.history.entries.count == 3)
        app.shell.togglePin("code:tradr:pnl")
        precondition(app.shell.pins.contains("code:tradr:pnl"))
        app.shell.togglePin("code:tradr:pnl")
        precondition(app.shell.pins.isEmpty)
        let url = URL(fileURLWithPath: "/tmp/example.txt")
        app.shell.addSources([url, url], projectID: "tradr")
        precondition(app.shell.attachedSources["tradr"]?.count == 1)
        precondition(app.shell.attachedSources["other"] == nil)
        app.openHome()
        app.approve(projectID: "tradr", taskID: "pnl")
        precondition(app.blotStimulus.context == .task("tradr:pnl") && app.activeBlotContext == .home)
        app.switchProduct(.work)
        app.openNewItem()
        precondition(app.workRoute == .home && app.shellSection == .chats)
        precondition(!app.shellSupportsProjectPanel && !app.shellPanelVisible)
        precondition(app.workChat.projects.map(\.id) == DemoData.workProjects.map(\.id))
        precondition(app.workChat.sessions.allSatisfy { !$0.messages.isEmpty && $0.projectID != nil })
        let demoChat = app.workChat.session("work-receipt")!
        let independentWork = WorkChatState()
        demoChat.send("Check that demo instances do not share mutable conversations")
        precondition(independentWork.session("work-receipt")?.messages.count == 2)
        app.openWorkChatProject("java-cart")
        precondition(app.product == .work && app.workChat.selectedProjectID == "java-cart" && app.workRoute == .home)
        let teamCount = app.workSessions.count
        app.workChatDraft = "Ordinary Work conversation"
        app.sendWorkChatMessage()
        let chat = app.currentWorkChat!
        precondition(chat.messages.count == 2 && chat.projectID == "java-cart" && app.workSessions.count == teamCount)
        precondition(app.activeBlotContext == .workChat(chat.id))
        app.workChatDraft = "Keep this draft"
        app.switchProduct(.code)
        app.switchProduct(.work)
        precondition(app.currentWorkChat?.id == chat.id && app.workChatDraft == "Keep this draft")
        let chatDestination = app.shellDestination
        app.shell.history.record(chatDestination)
        app.openSection(.scheduled)
        precondition(app.shellSection == .scheduled && !app.shellPanelVisible)
        app.shell.history.record(app.shellDestination)
        app.navigateHistory(-1)
        precondition(app.currentWorkChat?.id == chat.id && app.workChatDraft == "Keep this draft" && app.workChat.selectedProjectID == "java-cart")
        app.openSection(.skills)
        precondition(app.shellSection == .skills && !app.shellSupportsProjectPanel)
        app.openBlotChat()
        precondition(app.currentWorkChat?.id == chat.id && app.shellSection == .chats)
        app.openWorkRun("receipt")
        precondition(app.product == .code && app.shellSection == .motes)
        app.switchProduct(.work)
        precondition(!app.isMotes && app.currentWorkChat?.id == chat.id && !app.shellPanelVisible)
        let runStatus = app.currentWorkSession?.status
        app.handleEscape()
        precondition(app.currentWorkSession?.status == runStatus)
        app.switchProduct(.code)
        precondition(app.isMotes)
        app.openNewItem()
        precondition(app.teamRoute == .newRun)
        app.newRun.goal = "Verify local run"
        app.createLocalRun()
        let id = app.selectedRunID
        precondition(app.blotStimulus.context == .run(id))
        app.workDraft = "Preserve me"
        let manager = app.team.first { $0.role == .projectManager }!
        app.toggleAgent(.projectManager)
        precondition(app.team.first { $0.role == .projectManager }?.stateLabel == "paused")
        app.toggleAgent(.projectManager)
        precondition(app.team.first { $0.role == .projectManager }?.state == manager.state)
        app.pauseOrResumeRun()
        precondition(app.currentWorkSession?.status == .paused && app.activeBlotState == .idle)
        app.pauseOrResumeRun()
        precondition(app.team.first { $0.role == .projectManager }?.state == manager.state)
        app.paletteVisible = true
        app.handleEscape()
        precondition(!app.paletteVisible && app.currentWorkSession?.status == .running)
        app.handleEscape()
        precondition(app.currentWorkSession?.status == .stopped && app.workDraft == "Preserve me")
        let count = app.teamChat.count
        app.handleEscape()
        precondition(app.teamChat.count == count)

        let graph = GraphLayout.make(.communication).focused(on: .backend)
        precondition(graph.nodes.contains { $0.role == .backend })
        precondition(graph.nodes.count < GraphLayout.make(.communication).nodes.count)
        precondition(!graph.nodes.contains { $0.role == .qa || $0.role == .integrator })
        precondition(graph.labels.allSatisfy { label in graph.edges.contains { $0.id == label.edgeID } })
        let runtime = TestRuntime()
        let director = BlotDirector(now: { runtime.date }, random: { runtime.random($0) })
        var previous = BlotState.idle
        var lastBig: Date?
        var bigBeats = 0
        var lastExpression: BlotState?
        var firstScene: [BlotState] = []
        var idleStarted: Date?
        for _ in 0..<2400 {
            runtime.date.addTimeInterval(0.1)
            director.tick(.lively)
            if director.act != previous && director.act.isBig {
                if let lastBig {
                    let interval = runtime.date.timeIntervalSince(lastBig)
                    precondition(interval >= 5.9 && interval <= 10.2)
                }
                lastBig = runtime.date; bigBeats += 1
            }
            if director.act != previous && director.act != .idle {
                precondition(lastExpression != director.act)
                lastExpression = director.act
                if firstScene.count < 5 { firstScene.append(director.act) }
                if let idleStarted { precondition(runtime.date.timeIntervalSince(idleStarted) <= 1.2) }
                idleStarted = nil
            }
            if director.act != previous && director.act == .idle { idleStarted = runtime.date }
            previous = director.act
        }
        precondition(firstScene == [.glance, .curious, .happy, .nod, .stretch])
        precondition(bigBeats >= 26)
        // Different random seeds must preserve the authored pacing and scene order.
        let secondClock = TestRuntime()
        let second = BlotDirector(now: { secondClock.date }, random: { $0.upperBound })
        var secondScene: [BlotState] = []
        var secondPrevious = BlotState.idle
        for _ in 0..<100 {
            secondClock.date.addTimeInterval(0.1); second.tick(.lively)
            if second.act != secondPrevious && second.act != .idle { secondScene.append(second.act) }
            secondPrevious = second.act
        }
        precondition(Array(secondScene.prefix(5)) == firstScene)
        runtime.date.addTimeInterval(301)
        director.tick(.lively)
        if director.act == .idle { runtime.date.addTimeInterval(7); director.tick(.lively) }
        precondition(director.act == .sleep)
        director.stimulate(.typing)
        director.tick(.lively)
        precondition(director.act == .wakeUp)
        runtime.date.addTimeInterval(0.5); director.tick(.lively)
        precondition(director.act == .listening)
        director.stimulate(.failure); director.tick(.lively)
        precondition(director.act == .error)
        director.stimulate(.typing); director.tick(.lively)
        precondition(director.act == .error)
        runtime.date.addTimeInterval(1); director.tick(.lively)
        precondition(director.act == .listening)
        let cancelled = BlotDirector(wait: { _ in try await Task.sleep(for: .milliseconds(5)) })
        let scheduler = Task { await cancelled.run(.lively, intro: false) }
        try await Task.sleep(for: .milliseconds(20))
        scheduler.cancel()
        await scheduler.value
        let settled = cancelled.actStart
        try await Task.sleep(for: .milliseconds(20))
        precondition(cancelled.actStart == settled)
        print("PASS: Work chat isolation, Code Motes, contextual sidebar, history, pins, scoped sources/events, New run, Escape, authored scenes, steady pacing, sleep/wake and cancellation")
    }

    @MainActor private static func checkWorkspaceLibrary() async throws {
        let suite = "blot.workspace.check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = AccountPluginUsage(defaults: defaults)
        let first = AccountPlugin(id: "one", name: "One", icon: "puzzle", launchURL: URL(string: "https://example.com/one")!)
        let second = AccountPlugin(id: "two", name: "Two", icon: "puzzle", launchURL: URL(string: "https://example.com/two")!, usageCount: 2)
        var user = AuthUser(email: "first@blot.local", name: "First", installedPlugins: [first, second])
        precondition(usage.mostUsed(for: user).map(\.id) == ["two", "one"])
        for _ in 0..<3 { usage.recordOpening(first.id, for: user) }
        precondition(usage.mostUsed(for: user).map(\.id) == ["one", "two"])
        let other = AuthUser(email: "second@blot.local", name: "Second", installedPlugins: [first, second])
        precondition(usage.mostUsed(for: other).map(\.id) == ["two", "one"])
        user.installedPlugins = [second]
        precondition(usage.mostUsed(for: user).map(\.id) == ["two"])
        user.installedPlugins = []
        precondition(usage.mostUsed(for: user).isEmpty && usage.mostUsed(for: nil).isEmpty)

        let library = WorkspaceLibrary(defaults: defaults)
        library.selectAccount(user.email)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let imageURL = directory.appendingPathComponent("import-check.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
        try library.importImages([imageURL])
        precondition(library.images.count == 1)
        let importedImage = try library.images[0].load()
        precondition(importedImage.size.width == 2)
        let site = SavedSite(id: UUID(), name: "Example", url: URL(string: "https://example.com")!)
        let assistant = AssistantProfile(id: UUID(), name: "Editor", instructions: "Keep sentences concise.")
        library.saveSite(site)
        library.saveAssistant(assistant)
        let profile = ProfileDetails(name: "Preview Person", username: "preview_person", bio: "Build useful tools.")
        library.saveProfile(profile)
        library.featureSites([site.id, UUID()])
        precondition(library.profileDetails == profile && library.featuredSiteIDs == [site.id])
        library.selectAccount(other.email)
        precondition(library.images.isEmpty && library.sites.isEmpty && library.assistants.isEmpty && library.profileDetails == nil && library.featuredSiteIDs.isEmpty)
        library.selectAccount(user.email)
        precondition(library.sites.first?.id == site.id && library.assistants.first?.id == assistant.id)
        let restored = WorkspaceLibrary(defaults: defaults)
        restored.selectAccount(user.email)
        precondition(restored.sites.first?.id == site.id)
        precondition(restored.profileDetails == profile && restored.featuredSiteIDs == [site.id])
        let restoredImage = try restored.images[0].load()
        precondition(restoredImage.size.width == 2)
        let asynchronouslyRestored = WorkspaceLibrary(defaults: defaults)
        await asynchronouslyRestored.restoreAccount(user.email)
        precondition(asynchronouslyRestored.sites.first?.id == site.id && asynchronouslyRestored.images.count == 1)
        await asynchronouslyRestored.restoreAccount(other.email)
        precondition(asynchronouslyRestored.sites.isEmpty && asynchronouslyRestored.images.isEmpty)
        let cancelledRestore = Task { await asynchronouslyRestored.restoreAccount(user.email) }
        cancelledRestore.cancel()
        await cancelledRestore.value
        precondition(asynchronouslyRestored.sites.isEmpty)
        do {
            _ = try LocalPreviewReader.read(directory)
            preconditionFailure("Directories must not be read as previews")
        } catch LocalPreviewError.directory { }
        do {
            _ = try LocalPreviewReader.read(imageURL, maxBytes: 1)
            preconditionFailure("Preview size limits must be enforced")
        } catch LocalPreviewError.tooLarge { }
        let previewData = try LocalPreviewReader.read(imageURL)
        precondition(NSImage(data: previewData) != nil)
        library.removeImage(library.images[0].id)
        library.saveAssistant(AssistantProfile(id: assistant.id, name: "Editor", instructions: "Use plain language."))
        precondition(library.assistants.count == 1 && library.assistants.first?.instructions == "Use plain language.")
        library.removeSite(site.id)
        precondition(library.featuredSiteIDs.isEmpty)
        library.removeAssistant(assistant.id)
        library.selectAccount(nil)
        precondition(library.sites.isEmpty && library.assistants.isEmpty)

        let app = AppState()
        let home = app.shellDestination
        app.shell.history.record(home)
        app.openTool(.sites)
        app.shell.history.record(app.shellDestination)
        precondition(app.shellTitle == "Sites" && !app.shellSupportsProjectPanel && !app.shellPanelVisible && !app.shellSidebarVisible)
        app.navigateHistory(-1)
        precondition(app.activeTool == nil && app.shellSidebarVisible)
        app.navigateHistory(1)
        precondition(app.activeTool == .sites)
        app.openAssistantChat(assistant)
        precondition(app.activeTool == nil && app.currentWorkChat?.assistant?.instructions == assistant.instructions)
        precondition(app.currentWorkChat?.messages.isEmpty == true)
        app.openTool(.codeReview)
        app.openSection(.skills)
        precondition(app.activeTool == nil && app.shellSection == .skills)
        app.shell.history.record(app.shellDestination)
        app.openProfile()
        app.shell.history.record(app.shellDestination)
        precondition(app.profileVisible && !app.shellSidebarVisible && !app.shellPanelVisible && app.shellTitle == "Profile")
        app.navigateHistory(-1)
        precondition(!app.profileVisible && app.shellSection == .skills)
        app.navigateHistory(1)
        precondition(app.profileVisible)
        app.openTool(.sites)
        precondition(!app.profileVisible && app.activeTool == .sites)
        precondition(profile.initials == "PP")
        precondition(ProfileDetails(name: "kirill0983", username: "kirill0983").initials == "KI")
        precondition(!ProfileDetails(name: "Preview", username: "invalid name").isValid)
        print("PASS: plugin ordering and installation filtering, account isolation, library persistence, tool history and assistant instructions")
    }

    @MainActor private static func renderScreens(to output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let requestedSizes = ProcessInfo.processInfo.environment["BLOT_RENDER_SIZES"]
        let renderSizes: [(Int, Int)] = requestedSizes.map { value in
            value.split(separator: ",").map { item in
                let parts = item.split(separator: "x").compactMap { Int($0) }
                precondition(parts.count == 2 && parts[0] >= 1024 && parts[1] >= 666, "Invalid render size")
                return (parts[0], parts[1])
            }
        } ?? [(1024,768),(1440,900),(1312,751),(1710,983)]
        for light in [false, true] {
            let appearance = NSAppearance(named: light ? .aqua : .darkAqua)!
            NSApp.appearance = appearance
            for (width, height) in renderSizes {
                let requested = ProcessInfo.processInfo.environment["BLOT_RENDER_SCREENS"]?.split(separator: ",").map(String.init)
                let scenarios = MacRenderScenario.all.filter { requested == nil || requested!.contains($0.name) }
                if let requested {
                    precondition(Set(requested).isSubset(of: Set(MacRenderScenario.all.map(\.name))), "Unknown render scenario")
                }
                for scenario in scenarios {
                    let state = AppState()
                    state.currentUser = AuthUser(email: "preview@blot.local", name: "Yaroslav")
                    state.theme = light ? .light : .dark
                    state.settings.reduceMotion = true
                    scenario.configure(state)
                    let login: LoginViewModel?
                    if let screen = scenario.auth {
                        state.currentUser = nil
                        let model = LoginViewModel(lastEmail: "preview@blot.local")
                        model.screen = screen
                        login = model
                    } else { login = nil }
                    let root = MacRenderPreview(scenario: scenario, state: state, login: login)
                    let host = NSHostingView(rootView: root)
                    host.appearance = appearance
                    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
                    let window = NSWindow(contentRect: host.frame,
                        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.appearance = appearance
                    window.contentView = host
                    window.setFrame(NSRect(x: 0, y: 0, width: width, height: height), display: false)
                    host.layoutSubtreeIfNeeded()
                    if scenario.name != "loading-startup" {
                        try await Task.sleep(for: .milliseconds(120))
                    }
                    let canvas = window.contentView?.superview ?? host
                    canvas.layoutSubtreeIfNeeded()
                    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { fatalError("No bitmap") }
                    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
                    let name = "\(scenario.name)-\(width)x\(height)-\(light ? "light" : "dark").png"
                    try data.write(to: output.appendingPathComponent(name))
                    print(name)
                    window.contentView = nil
                    window.close()
                }
            }
        }
    }
}

@MainActor private final class TestRuntime {
    var date = Date(timeIntervalSince1970: 1_000_000)
    private var seed: UInt64 = 1287
    func random(_ range: ClosedRange<Double>) -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(seed >> 11) / Double(UInt64.max >> 11)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
