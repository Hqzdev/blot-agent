import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation
import WebKit

private actor BrowserModelCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}
private struct BrowserVerificationModel: ChatModel {
    let origin: String
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let results = request.messages.filter { $0.role == "tool" }
                func result(_ name: String) -> [String: ChatJSON]? {
                    guard let message = results.last(where: { $0.name == name }), let value = try? JSONDecoder().decode(ChatJSON.self, from: Data(message.content.utf8)), case .object(let fields) = value else { return nil }; return fields
                }
                let call: ChatToolCall
                if result("browser_open") == nil { call = .init(id: "open", name: "browser_open", arguments: .object(["url": .string(origin + "/page")])) }
                else if result("browser_snapshot") == nil { call = .init(id: "snapshot", name: "browser_snapshot", arguments: .object(["tab_id": result("browser_open")!["tab_id"]!])) }
                else if result("browser_click") == nil {
                    let page = result("browser_snapshot")!
                    guard case .array(let elements) = page["elements"], let element = elements.first(where: { item in if case .object(let f) = item { return f["label"] == .string("Change status") }; return false }), case .object(let target) = element else { throw WorkspaceBrowserError.stalePage }
                    call = .init(id: "click", name: "browser_click", arguments: .object(["tab_id": page["tab_id"]!, "document_id": page["document_id"]!, "element_id": target["id"]!]))
                } else {
                    guard result("browser_click")?["state"] == .string("completed") else { throw WorkspaceBrowserError.unknown }
                    continuation.yield(.text("The website button was clicked after confirmation.")); continuation.yield(.finished(.stop)); continuation.finish(); return
                }
                guard request.tools.contains(where: { $0.name == call.name }) else { throw WorkspaceBrowserError.denied }
                continuation.yield(.usage(try ChatModelUsage(inputTokens: 50, outputTokens: 10)))
                continuation.yield(.toolCall(call)); continuation.yield(.finished(.toolCalls)); continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}
@MainActor
enum BrowserModelVerification {
    static func run(origin: String, directory: URL, automatic: Bool = false) async throws {
        let database = directory.appendingPathComponent("model.sqlite")
        let repository = try WorkspaceRepository(url: database), identity = try await repository.localIdentity()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Web worker", instructions: "Use the approved website tools", modelID: "compatible"))
        let conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Browser test", agentID: agent)
        let service = try LocalWorkspaceService(databaseURL: database, repository: repository, identity: identity, maximumOutputTokens: 64,
            mcpCredentials: BrowserModelCredentials(), makeBrowser: { id, folder in WorkspaceBrowserController(profileID: id, directory: folder, ephemeral: true) },
            automaticBrowserAccess: automatic, makeModel: { _ in BrowserVerificationModel(origin: origin) })
        _ = try await service.load()
        if !automatic { try await service.browserService().configure(agents: [agent], origins: [origin]) }
        let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: conversation, content: "Open the approved test page and click Change status after confirmation")
        let source = try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID)!
        let approvals = _Concurrency.Task { @MainActor in
            while !_Concurrency.Task.isCancelled {
                if let pending = service.appleIntegrations.interactions.pending {
                    precondition(pending.details.contains("Change status"))
                    service.appleIntegrations.interactions.finish(pending.id, result: .success(.bool(true)))
                }
                do { try await _Concurrency.Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
        defer { approvals.cancel() }
        for try await _ in try await service.responses(to: source) {}
        let snapshot = try await service.currentSnapshot()
        precondition(snapshot.toolInvocations?.contains { $0.state == .succeeded } == true)
        precondition(snapshot.messages.contains { $0.role == .assistant && $0.content.contains("website button") })
        guard let tab = service.workspaceBrowser.selectedID, let page = service.workspaceBrowser.webView(for: tab) else { throw WorkspaceBrowserError.unavailable }
        let status = try await page.callAsyncJavaScript("return document.getElementById('status').textContent;", contentWorld: .page) as? String
        precondition(status == "clicked")
        try await service.close()
        print("PASS: chat → actual WebKit → DOM → exact confirmation → durable invocation → model result")
    }

    static func selectedTab(origin: String, directory: URL, group: Bool, automatic: Bool = false) async throws {
        let scenarioDirectory = directory.appendingPathComponent((automatic ? "auto-" : "") + (group ? "group-selected" : "direct-selected"), isDirectory: true)
        let database = scenarioDirectory.appendingPathComponent("workspace.sqlite")
        let repository = try WorkspaceRepository(url: database), identity = try await repository.localIdentity()
        let agents = WorkspaceAgentService(repository: repository, identity: identity)
        let agent = try await agents.save(commandID: UUID(), draft: .init(name: "Reader", instructions: "Inspect the website when asked", modelID: "compatible"))
        let chat: UUID
        if group {
            let other = try await agents.save(commandID: UUID(), draft: .init(name: "Colleague", instructions: "Help only when needed", modelID: "compatible"))
            chat = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "Web group", agentIDs: [agent, other])
        } else {
            chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Web chat", agentID: agent)
        }
        let service = try LocalWorkspaceService(databaseURL: database, repository: repository, identity: identity, maximumOutputTokens: 256,
            mcpCredentials: BrowserModelCredentials(), makeBrowser: { id, folder in WorkspaceBrowserController(profileID: id, directory: folder, ephemeral: true) },
            automaticBrowserAccess: automatic, makeModel: { _ in SelectedBrowserVerificationModel() })
        _ = try await service.load()
        _ = try service.workspaceBrowser.open(origin + "/page")
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while service.workspaceBrowser.selectedTab?.loading == true {
            guard ContinuousClock.now < deadline else { throw WorkspaceBrowserError.timeout }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        func ask() async throws {
            let id = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Посмотри, я открыл сайт, ты его видишь?")
            let source = try await repository.record(BlotV3.Message.self, id: id, workspaceID: identity.workspaceID)!
            for try await _ in try await service.responses(to: source) {}
        }
        try await ask()
        let deniedSnapshot = try await service.currentSnapshot()
        if automatic {
            precondition(deniedSnapshot.messages.contains { $0.role == .assistant && $0.content == "I see the Local test page inside Blot." })
        } else {
            precondition(deniedSnapshot.messages.contains { $0.role == .assistant && $0.content == "Enable agent access to the current site." })
            try await service.browserService().configure(agents: [agent], origins: [origin]); try await ask()
        }
        let result = try await service.currentSnapshot()
        precondition(result.messages.contains { $0.role == .assistant && $0.content == "I see the Local test page inside Blot." })
        precondition(service.workspaceBrowser.tabs.count == 1)
        try await service.close()
        print("PASS: \(group ? "group conversation" : "direct chat") → manual tab; \(automatic ? "works immediately without site/agent setup" : "legacy grants remain enforced")")
    }
}

private struct SelectedBrowserVerificationModel: ChatModel {
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let systems = request.messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
            continuation.yield(.usage(try! ChatModelUsage(inputTokens: 50, outputTokens: 10)))
            if systems.contains("Select the interaction mode") {
                continuation.yield(.text("{\"mode\":\"conversation\"}")); continuation.yield(.finished(.stop))
            } else if let result = request.messages.last(where: { $0.role == "tool" && $0.name == "browser_snapshot" }) {
                precondition(result.content.contains("Local test page") && result.content.contains("read_only_user_tab"))
                precondition(!result.content.contains("never-expose"))
                continuation.yield(.text("I see the Local test page inside Blot.")); continuation.yield(.finished(.stop))
            } else {
                precondition(systems.contains("A website tab is open in Blot") || systems.contains("Blot has a built-in browser"))
                if request.tools.contains(where: { $0.name == "browser_snapshot" }) {
                    if systems.contains("ordinary group conversation") { precondition(request.tools.allSatisfy { ["browser_snapshot", "browser_tabs"].contains($0.name) }) }
                    continuation.yield(.toolCall(.init(id: "selected", name: "browser_snapshot", arguments: .object([:])))); continuation.yield(.finished(.toolCalls))
                } else {
                    continuation.yield(.text("Enable agent access to the current site.")); continuation.yield(.finished(.stop))
                }
            }
            continuation.finish()
        }
    }
}
