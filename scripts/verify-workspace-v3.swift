import AppKit
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

@MainActor
@main
struct WorkspaceVerification {
    static func main() async throws {
        if CommandLine.arguments.contains("--responsiveness-only") {
            try await verifyPresentationWrites()
            try verifyMessageIndex()
            return
        }
        if CommandLine.arguments.contains("--startup-only") {
            try await verifyStartupRestoration()
            print("PASS: startup waits for session restoration, coalesces loads, and settles saved, absent and failed sessions")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--live-model-check"), index + 1 < CommandLine.arguments.count {
            try await verifyLiveModel(configurationURL: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-live-settings"), index + 1 < CommandLine.arguments.count {
            try renderLiveSettings(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-live-team"), index + 1 < CommandLine.arguments.count {
            try renderLiveTeam(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        if CommandLine.arguments.contains("--browser-launch-only") {
            try await verifyBrowserLaunch()
            print("PASS: website launch waits for restoration, rejects malformed URLs, and starts one sign-in")
            return
        }
        if CommandLine.arguments.contains("--local-only") {
            try await verifyLocalWorkspace()
            print("PASS: durable UI commands, streaming, explicit retry and reopening (injected model; no Keychain/network)")
            return
        }
        let references = WorkspaceReference.all
        precondition(references.count == 53)
        precondition(references.filter { $0.platform == .desktop }.count == 28)
        precondition(references.filter { $0.platform == .ios }.count == 25)
        for r in references { precondition(FileManager.default.fileExists(atPath: r.path), r.path) }
        let live = WorkspaceStore(route: .signIn)
        precondition(live.snapshot.agents.isEmpty && live.snapshot.messages.isEmpty)
        live.form.account.email = "invalid"; await live.perform(.signIn)
        precondition(live.error != nil && live.route == .signIn)
        live.form.account.email = "user@blot.local"; live.form.account.password = "long-password"
        await live.perform(.signIn, next: .chats)
        precondition(live.error != nil && live.route == .signIn && !live.busy)
        for action in [WorkspaceAction.signIn, .register, .oauth] {
            let unauthorized = WorkspaceStore(mode: .live, route: .signIn, service: UnavailableWorkspaceService())
            await unauthorized.perform(action, next: .chats)
            precondition(unauthorized.error != nil && unauthorized.snapshot.messages.isEmpty)
            precondition(unauthorized.snapshot.conversations.isEmpty && unauthorized.route == .signIn)
        }
        let preview = WorkspaceStore(mode: .preview, route: .chats)
        precondition(preview.error == nil && preview.snapshot.agents.count == 6)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let source = try decoder.decode(WorkspaceSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: "fixtures/v3/presentation.json")))
        precondition(source == preview.snapshot, "Embedded preview data must match the shared fixture")
        precondition(preview.currentMessages.count == 2)
        preview.openConversation(preview.snapshot.conversations[1].metadata.id)
        precondition(preview.currentMessages.isEmpty)
        preview.selectedConversationID = preview.snapshot.conversations[0].metadata.id
        preview.form.schedule.name = "Independent schedule"
        preview.form.agent.name = "Verifier"; preview.form.agent.instructions = "Check the result"
        await preview.perform(.createAgent, next: .agents)
        precondition(preview.snapshot.agents.count == 7 && preview.route == .agents)
        precondition(preview.form.schedule.name == "Independent schedule")
        preview.form.composer.draft = " "; await preview.perform(.send)
        precondition(preview.error != nil)
        preview.form.composer.draft = "Test delivery"; await preview.perform(.send)
        precondition(preview.snapshot.messages.last?.delivery == .saved && preview.form.composer.draft.isEmpty)
        preview.navigate(.chat); preview.navigate(.running); preview.back()
        precondition(preview.route == .chat)
        let gate = GateService()
        let gated = WorkspaceStore(mode: .preview, service: gate)
        gated.form.composer.draft = "One command"
        gated.form.account.password = "must-not-leave-auth"
        gated.form.model.secret = "must-not-leave-model-settings"
        let first = _Concurrency.Task { await gated.perform(.send) }
        await _Concurrency.Task.yield()
        await gated.perform(.send)
        precondition(gate.calls == 1 && gated.busy)
        gate.finish(); await first.value
        precondition(!gated.busy)
        try await verifyLocalWorkspace()
        try await verifyStartupRestoration()
        print("PASS: 53 references, live isolation, authentication required, form validation, preview mutations, navigation, duplicate prevention")
        print("PASS: live UI adapter writes SQLite, streams through recorder, retries without resending user message, and restores after reopening (injected model)")
        if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
            try render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true))
        }
    }
    static func verifyPresentationWrites() async throws {
        let writer = WorkspacePresentationWriter()
        var writes: [Data] = []
        var state = WorkspacePresentationState(drafts: [:], interactions: .init(), personalization: .init(),
            firstName: "", lastName: "", email: "")
        let id = UUID()
        for index in 0..<200 {
            state.drafts[id] = WorkspaceComposerForm(draft: "Edit \(index)")
            writer.schedule(state, immediately: false) { writes.append($0) }
        }
        await writer.flush()
        precondition(writes.count == 1)
        let initial = try JSONDecoder().decode(WorkspacePresentationState.self, from: writes[0])
        precondition(initial.drafts[id]?.draft == "Edit 199")
        writer.schedule(state, immediately: true) { writes.append($0) }
        await writer.flush()
        precondition(writes.count == 1)
        state.drafts[id]?.draft = "Latest before backgrounding"
        writer.schedule(state, immediately: false) { writes.append($0) }
        writer.schedule(state, immediately: true) { writes.append($0) }
        await writer.flush()
        precondition(writes.count == 2)
        let latest = try JSONDecoder().decode(WorkspacePresentationState.self, from: writes[1])
        precondition(latest.drafts[id]?.draft == state.drafts[id]?.draft)
        writer.reset()
        print("PASS: 200 rapid edits produce one write; duplicate data is skipped and lifecycle flush preserves the latest draft")
    }

    static func verifyMessageIndex() throws {
        let ids = (0..<100).map { _ in UUID() }
        let owner = UUID(), workspace = UUID(), now = Date()
        let messages = try ids.flatMap { conversation in
            try (0..<100).reversed().map { position in
                try BlotV3.Message(metadata: .init(id: UUID(), ownerId: owner, workspaceId: workspace, version: 1,
                    createdAt: now, updatedAt: now), conversationId: conversation, role: .assistant,
                    content: "Test", delivery: .completed, commandId: UUID(), artifactIds: [], position: position)
            }
        }
        var expected: [UUID] = [], actual: [UUID] = []
        let clock = ContinuousClock()
        let baseline = clock.measure {
            for _ in 0..<10 {
                for id in ids { expected.append(WorkspaceMessageOrder.ordered(messages.filter { $0.conversationId == id }).last!.metadata.id) }
            }
        }
        let indexed = clock.measure {
            let index = WorkspaceMessageIndex(messages)
            precondition(index.messages(in: nil).isEmpty && index.messages(in: UUID()).isEmpty)
            for _ in 0..<10 {
                for id in ids { actual.append(index.messages(in: id).last!.metadata.id) }
            }
        }
        precondition(expected == actual)
        print("PASS: 10,000 messages / 1,000 conversation reads preserve ordering; repeated filter/sort=\(baseline), indexed=\(indexed)")
    }
    static func verifyStartupRestoration() async throws {
        precondition(!WorkspaceStore(mode: .preview, route: .welcome).isRestoringSession)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = try await local.currentSnapshot()
        for outcome in [Result<WorkspaceSnapshot?, Error>.success(saved),
                        .success(nil), .failure(WorkspaceServiceError.unavailable)] {
            let service = StartupGateService(commands: local)
            let store = WorkspaceStore(mode: .live, service: service)
            precondition(store.isRestoringSession)
            let first = _Concurrency.Task { await store.loadWorkspace() }
            try await waitUntil { service.loads == 1 }
            let second = _Concurrency.Task { await store.loadWorkspace() }
            await _Concurrency.Task.yield()
            precondition(store.isRestoringSession && service.loads == 1)
            service.finish(outcome)
            await first.value; await second.value
            precondition(!store.isRestoringSession)
            switch outcome {
            case .success(.some(let saved)):
                precondition(store.snapshot.ownerID == saved.ownerID && !store.route.isAuthentication && store.error == nil)
            case .success(.none):
                precondition(store.route == .welcome && store.error == nil)
            case .failure:
                precondition(store.route == .welcome && store.error != nil)
            }
        }
        try await local.close()
    }
    static func verifyBrowserLaunch() async throws {
        let service = BrowserLaunchGateService()
        let store = WorkspaceStore(mode: .live, service: service)
        for raw in ["blot-agent-ios:/oauth/start", "blot-agent-macos://untrusted/oauth/start", "blot-agent-macos:/oauth/start?access_token=invalid", "blot-agent-macos:/oauth/account"] {
            store.handleBrowserLaunch(URL(string: raw)!)
        }
        await _Concurrency.Task.yield()
        precondition(service.calls == 0)
        let startup = _Concurrency.Task { await store.loadWorkspace() }
        store.handleBrowserLaunch(URL(string: "blot-agent-macos:/oauth/start")!)
        store.handleBrowserLaunch(URL(string: "blot-agent-macos:/oauth/start")!)
        try await waitUntil { service.calls == 1 }
        precondition(service.loads == 1 && store.busy)
        service.finish()
        await startup.value
        try await waitUntil { !store.busy }
        precondition(service.calls == 1 && store.snapshot.ownerID == nil && store.error != nil)
    }

    static func renderLiveTeam(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for width in [1440, 2160] {
            let store = WorkspaceStore(mode: .preview, route: .chat)
            store.language = "ru"
            let size = CGSize(width: width, height: 1000)
            let root = MacLiveTeamWorkspace().environment(store).blotTheme(.light)
                .environment(\.colorScheme, .light).frame(width: size.width, height: size.height)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Could not render team layout") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let rendered = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode team layout") }
            try rendered.write(to: directory.appendingPathComponent("team-live-\(width).png"))
            window.contentView = nil; window.close()
        }
        print("PASS: production team layout rendered at 1440 and 2160 points using isolated preview fixtures")
    }

    static func renderLiveSettings(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // System notification queries require an actual app bundle, not this CLI render host.
        for route in [WorkspaceRoute.settings, .appearance, .personalization] {
            let store = WorkspaceStore(mode: .preview, route: .chat)
            store.language = "ru"
            let size = CGSize(width: 1440, height: 900)
            let root = MacLiveTeamSettings(route: route).environment(store).blotTheme(.light)
                .environment(\.colorScheme, .light).frame(width: size.width, height: size.height)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.frame = NSRect(origin: .zero, size: size); host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)); host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Could not render settings") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode settings") }
            try png.write(to: directory.appendingPathComponent("settings-\(route.rawValue).png"))
            window.contentView = nil; window.close()
        }
        print("PASS: original settings layout renders general, appearance and personalization without a demo presentation")
    }

    static func verifyLiveModel(configurationURL: URL) async throws {
        let configuration = try AppleInstallationConfiguration.decode(Data(contentsOf: configurationURL))
        let model = try configuration.makeModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"),
            maximumOutputTokens: configuration.gigaChat.outputTokens, runTokenBudget: configuration.gigaChat.runTokenBudget,
            makeModel: { _ in model })
        do {
            let store = WorkspaceStore(mode: .live, service: service)
            await store.loadWorkspace()
            store.form.agent = WorkspaceAgentForm(name: "Verification", instructions: "Отвечай кратко, одним словом.", toolIDs: ["memory_candidate"])
            await store.perform(.createAgent)
            guard store.error == nil, store.selectedAgentID != nil else { throw CheckFailure.timedOut }
            await store.perform(.createConversation, next: .chat)
            for index in 0..<2 {
                store.form.composer.draft = "Ответь одним словом: работает"
                await store.perform(.send)
                let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                while store.isReplying {
                    guard ContinuousClock.now < deadline else { throw CheckFailure.timedOut }
                    try await _Concurrency.Task.sleep(for: .milliseconds(50))
                }
                guard store.error == nil, store.currentMessages.count == (index + 1) * 2,
                      let response = store.currentMessages.last, response.role == .assistant,
                      response.delivery == .completed, !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("Live app model verification failed: \(store.error ?? "missing completed response")")
                    throw CheckFailure.timedOut
                }
                print("PASS: live agent with tools, conversation turn=\(index + 1), completed reply characters=\(response.content.count)")
            }
            try await service.close()
            try FileManager.default.removeItem(at: directory)
        } catch {
            try? await service.close()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func verifyLocalWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var services: [LocalWorkspaceService] = []
        do {
            let databaseURL = directory.appendingPathComponent("workspace-v3.sqlite")
            let localService = try LocalWorkspaceService(databaseURL: databaseURL, makeModel: { _ in ContractChatModel() })
            services.append(localService)
            let local = WorkspaceStore(mode: .live, route: .chats, service: localService)
            await local.loadWorkspace()
            await local.perform(.createConversation, next: .chat)
            local.form.composer.draft = "Durable local UI command"
            await local.perform(.send)
            try await waitUntil { !local.isReplying }
            precondition(local.error == nil && local.currentMessages.count == 2)
            precondition(local.currentMessages.last?.content == "Contract response" && local.currentMessages.last?.delivery == .completed)
            let userID = local.currentMessages[0].metadata.id
            local.retryResponse(to: userID)
            try await waitUntil { !local.isReplying }
            precondition(local.currentMessages.filter { $0.role == .user }.count == 1 && local.currentMessages.count == 3)
            let reopenedService = try LocalWorkspaceService(databaseURL: databaseURL, makeModel: { _ in ContractChatModel() })
            services.append(reopenedService)
            let reopened = WorkspaceStore(mode: .live, route: .chats, service: reopenedService)
            await reopened.loadWorkspace()
            precondition(reopened.snapshot.messages.count == 3 && reopened.snapshot.conversations.count == 1)
            let cancelURL = directory.appendingPathComponent("cancel.sqlite")
            let cancelService = try LocalWorkspaceService(databaseURL: cancelURL, makeModel: { _ in SuspendedChatModel() })
            services.append(cancelService)
            let cancel = WorkspaceStore(mode: .live, route: .chats, service: cancelService)
            await cancel.loadWorkspace()
            await cancel.perform(.createConversation, next: .chat)
            cancel.form.composer.draft = "Stop this response"
            await cancel.perform(.send)
            try await waitUntil { cancel.currentMessages.last?.delivery == .running }
            precondition(cancel.currentReplyDraft != nil)
            precondition(!cancel.currentMessages.filter(WorkspaceMessagePresentation.isVisible).contains { $0.role == .assistant })
            // Reopening the view on an active service must not mark its live stream interrupted.
            await cancel.loadWorkspace()
            precondition(cancel.currentMessages.last?.delivery == .running)
            do {
                _ = try await cancelService.responses(to: cancel.currentMessages[0])
                preconditionFailure("A conversation may not start a second live generation")
            } catch WorkspaceStorageError.permissionDenied {}
            cancel.stopReply()
            try await waitUntil { !cancel.isReplying && cancel.currentMessages.last?.delivery == .canceled }
            let canceledService = try LocalWorkspaceService(databaseURL: cancelURL, makeModel: { _ in ContractChatModel() })
            services.append(canceledService)
            let canceled = WorkspaceStore(mode: .live, route: .chats, service: canceledService)
            await canceled.loadWorkspace()
            precondition(canceled.snapshot.messages.count == 2)
            precondition(canceled.snapshot.messages.last?.delivery == .canceled)
        } catch {
            for service in services { try? await service.close() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        for service in services { try await service.close() }
        try FileManager.default.removeItem(at: directory)
    }

    enum CheckFailure: Error { case timedOut }
    static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CheckFailure.timedOut }
            try await _Concurrency.Task.sleep(for: .milliseconds(1))
        }
    }

    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sizes: [CGSize] = [CGSize(width: 1440, height: 900), CGSize(width: 1100, height: 740)]
        var manifest: [[String: String]] = []
        for reference in WorkspaceReference.all where reference.platform == .desktop {
            for dark in [false, true] {
                for size in sizes {
                    let store = WorkspaceStore(mode: .preview, route: reference.route)
                    let root = WorkspaceRootView(store: store)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .preferredColorScheme(dark ? .dark : .light)
                        .frame(width: size.width, height: size.height)
                    let host = NSHostingView(rootView: root)
                    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    host.appearance = NSApp.appearance
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.appearance = NSApp.appearance
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    host.frame = NSRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
                    host.displayIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let name = "\(reference.file)-\(Int(size.width))x\(Int(size.height))-\(dark ? "dark" : "light").png"
                    let data = bitmap.representation(using: .png, properties: [:])!
                    try data.write(to: directory.appendingPathComponent(name))
                    manifest.append(["reference": reference.path, "capture": name, "theme": dark ? "dark" : "light"])
                    window.contentView = nil; window.close()
                }
            }
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        print("PASS: rendered \(manifest.count) Mac frames")
    }
}

@MainActor
private final class GateService: WorkspaceService {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        precondition(request.form.account.password.isEmpty && request.form.model.secret.isEmpty)
        calls += 1
        await withCheckedContinuation { continuation = $0 }
        return snapshot
    }
    func finish() { continuation?.resume(); continuation = nil }
}

private struct ContractChatModel: ChatModel {
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.text("Contract "))
            continuation.yield(.text("response"))
            continuation.yield(.finished(.stop))
            continuation.finish()
        }
    }
}

/// A stream that stalls after its first delta, as a network connection can do.
private struct SuspendedChatModel: ChatModel {
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in continuation.yield(.text("Partial")) }
    }
}

@MainActor
private final class StartupGateService: WorkspaceService, WorkspaceCommandProviding {
    let workspaceCommands: (any WorkspaceCommandService)?
    private(set) var loads = 0
    private var continuation: CheckedContinuation<WorkspaceSnapshot?, Error>?
    init(commands: any WorkspaceCommandService) { workspaceCommands = commands }
    func load() async throws -> WorkspaceSnapshot? {
        loads += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        throw WorkspaceServiceError.unavailable
    }
    func finish(_ result: Result<WorkspaceSnapshot?, Error>) {
        continuation?.resume(with: result); continuation = nil
    }
}

@MainActor
private final class BrowserLaunchGateService: WorkspaceService {
    private(set) var calls = 0
    private(set) var loads = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func load() async throws -> WorkspaceSnapshot? {
        loads += 1
        await _Concurrency.Task.yield()
        return nil
    }
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        precondition(request.action == .oauth)
        calls += 1
        await withCheckedContinuation { continuation = $0 }
        throw WorkspaceServiceError.unavailable
    }
    func finish() { continuation?.resume(); continuation = nil }
}
