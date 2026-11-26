import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct CapabilityFixture: Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let agent: UUID
    let source: UUID
    init(request: String = "Create and reuse a budget skill, and connect Notes when needed.", toolIDs: [String] = ["read"]) async throws {
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("capabilities.sqlite"))
        identity = try await repository.localIdentity()
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Worker", instructions: "Help", toolIDs: toolIDs))
        let chats = WorkspaceChatService(repository: repository, identity: identity)
        let chat = try await chats.createConversation(commandID: UUID(), title: "Capabilities", agentID: agent)
        source = try await chats.sendMessage(commandID: UUID(), conversationID: chat, content: request)
    }
    var context: WorkspaceToolContext { .init(sourceMessageID: source, taskID: nil,
        allowedToolIDs: ["skill_list", "skill_read", "skill_create", "skill_run", "plugin_catalog", "plugin_connect"], agentID: agent) }
    var creator: ChatToolCall { .init(id: "save-budget", name: "skill_create", arguments: .object([
        "name": .string("Budget check"), "instructions": .string("Check {{budget}} and report the total."),
        "parameters": .array([.object(["name": .string("budget"), "required": .bool(true)])]), "tool_ids": .array([.string("read")])])) }
    func pendingCard() async throws -> BlotV3.ConversationCard {
        for _ in 0..<200 {
            if let card = try await repository.projection(identity: identity).cards.first { return card }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        throw WorkspaceStorageError.missingRecord
    }
}

private struct CapabilityDirectory: WorkspacePluginDirectory {
    let fixture: CapabilityFixture
    func plugins() async throws -> [WorkspacePluginDescriptor] {
        [.init(id: "notes", name: "Notes", summary: "Test integration", available: true),
         .init(id: "unavailable", name: "Unavailable", summary: "No setup", available: false)]
    }
    func isConnected(pluginID: String, agentID: UUID) async throws -> Bool {
        try await fixture.repository.projection(identity: fixture.identity).connections.contains {
            $0.pluginId == pluginID && $0.deviceId == fixture.identity.deviceID && $0.state == .connected
        }
    }
    func connect() async throws {
        try await WorkspaceExternalAccess(repository: fixture.repository, identity: fixture.identity).save(id: UUID(), plugin: "notes",
            service: "Notes", account: "test", scopes: ["read"])
    }
}

@Test func agentStartsWithSkillCreatorAndCanSaveReadAndQueueItsOwnSkill() async throws {
    let f = try await CapabilityFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let tools = WorkspaceSkillTools(repository: f.repository, identity: f.identity)
    #expect(Set(try await tools.availableDefinitions(context: f.context).map(\.name)) == ["skill_list", "skill_read", "skill_create", "skill_run"])
    let empty = try await tools.execute(.init(id: "list", name: "skill_list", arguments: .object([:])), context: f.context)
    guard case .object(let listing) = empty, case .array(let builtIn) = listing["built_in"] else { Issue.record("Missing Skill Creator"); return }
    #expect(builtIn.count == 1)
    let result = try await tools.execute(f.creator, context: f.context)
    #expect(try await tools.execute(f.creator, context: f.context) == result)
    let projection = try await f.repository.projection(identity: f.identity)
    let skill = try #require(projection.skills.first)
    #expect(projection.skills.count == 1 && projection.skillRevisions.count == 1)
    #expect(WorkspaceSkillAccess.assignments(projection.grants).contains { $0.skillID == skill.metadata.id && $0.agentID == f.agent && $0.assigned })
    let read = try await tools.execute(.init(id: "read-skill", name: "skill_read", arguments: .object(["skill_id": .string(skill.metadata.id.uuidString)])), context: f.context)
    guard case .object(let fields) = read else { Issue.record("Missing skill detail"); return }
    #expect(fields["instructions"] == .string("Check {{budget}} and report the total."))
    #expect(projection.tasks.isEmpty, "Saving must not execute the skill")
    let chat = try #require(projection.conversations.first)
    let next = try await WorkspaceChatService(repository: f.repository, identity: f.identity).sendMessage(commandID: UUID(), conversationID: chat.metadata.id,
        content: "Run the saved skill with budget 12000 + 28000.")
    let runContext = WorkspaceToolContext(sourceMessageID: next, taskID: nil, allowedToolIDs: f.context.allowedToolIDs, agentID: f.agent)
    _ = try await tools.execute(.init(id: "run", name: "skill_run", arguments: .object(["skill_id": .string(skill.metadata.id.uuidString),
        "values": .array([.object(["name": .string("budget"), "value": .string("12000 + 28000")])])])), context: runContext)
    #expect(try await f.repository.projection(identity: f.identity).tasks.first?.goal == "Check 12000 + 28000 and report the total.")
}

@Test func skillCreatorCannotGrantToolsOrIgnoreReadOnlyRequests() async throws {
    let f = try await CapabilityFixture(request: "Read only. Do not create or change anything.")
    defer { cleanupWorkspaceTestStorage(f.directory) }
    let tools = WorkspaceSkillTools(repository: f.repository, identity: f.identity)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await tools.execute(f.creator, context: f.context) }
    #expect(try await f.repository.projection(identity: f.identity).skills.isEmpty)
    let writable = try await CapabilityFixture(); defer { cleanupWorkspaceTestStorage(writable.directory) }
    var fields: [String: ChatJSON] = [:]
    if case .object(let values) = writable.creator.arguments { fields = values }
    fields["tool_ids"] = .array([.string("unassigned_external_tool")])
    let result = try await WorkspaceSkillTools(repository: writable.repository, identity: writable.identity)
        .execute(.init(id: "escalate", name: "skill_create", arguments: .object(fields)), context: writable.context)
    guard case .object(let error) = result else { Issue.record("Missing validation result"); return }
    #expect(error["error"] == .string("tools_unavailable"))
    #expect(try await writable.repository.projection(identity: writable.identity).skills.isEmpty)
}

@Test func skillCreatorReplayDoesNotRestoreAnAssignmentRevokedByTheOwner() async throws {
    let f = try await CapabilityFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let tools = WorkspaceSkillTools(repository: f.repository, identity: f.identity)
    _ = try await tools.execute(f.creator, context: f.context)
    let projection = try await f.repository.projection(identity: f.identity)
    let skill = try #require(projection.skills.first)
    try await WorkspaceSkillAssignmentService(repository: f.repository, identity: f.identity).set(commandID: UUID(),
        skillID: skill.metadata.id, agentID: f.agent, assigned: false, expectedVersion: 1)
    await #expect(throws: WorkspaceSkillError.notAssigned) { _ = try await tools.execute(f.creator, context: f.context) }
    #expect(!WorkspaceSkillAccess.assignments(try await f.repository.projection(identity: f.identity).grants).contains { $0.assigned })
}

@Test func pluginConnectionCardWaitsAndRejectsAnUnverifiedConnectedAnswer() async throws {
    let f = try await CapabilityFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let tools = WorkspacePluginTools(repository: f.repository, identity: f.identity, directory: CapabilityDirectory(fixture: f))
    let call = ChatToolCall(id: "connect", name: "plugin_connect", arguments: .object(["plugin_id": .string("notes"), "reason": .string("Create the requested note")]))
    let worker = _Concurrency.Task { try await tools.execute(call, context: f.context) }; defer { worker.cancel() }
    let card = try await f.pendingCard()
    #expect(card.kind == "connectionRequest" && card.state == "pending")
    #expect(try await f.repository.projection(identity: f.identity).connections.isEmpty)
    try await WorkspaceConversationCardService(repository: f.repository, identity: f.identity).respond(commandID: UUID(), cardID: card.metadata.id,
        expectedVersion: card.metadata.version, response: .init(action: "connected"))
    let result = try await worker.value
    guard case .object(let fields) = result else { Issue.record("Missing result"); return }
    #expect(fields["state"] == .string("not_connected") && fields["access_granted"] == .bool(false))
    #expect(try await f.repository.projection(identity: f.identity).connections.isEmpty)
}

@Test func pluginConnectionDismissalAndUnknownPluginsCannotCreateAccess() async throws {
    let f = try await CapabilityFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let tools = WorkspacePluginTools(repository: f.repository, identity: f.identity, directory: CapabilityDirectory(fixture: f))
    await #expect(throws: WorkspaceToolError.invalidArguments) {
        _ = try await tools.execute(.init(id: "unknown", name: "plugin_connect", arguments: .object(["plugin_id": .string("invented"), "reason": .string("Work")])), context: f.context)
    }
    let call = ChatToolCall(id: "connect", name: "plugin_connect", arguments: .object(["plugin_id": .string("notes"), "reason": .string("Create the requested note")]))
    let worker = _Concurrency.Task { try await tools.execute(call, context: f.context) }; defer { worker.cancel() }
    let card = try await f.pendingCard()
    try await WorkspaceConversationCardService(repository: f.repository, identity: f.identity).respond(commandID: UUID(), cardID: card.metadata.id,
        expectedVersion: card.metadata.version, response: .init(action: "dismiss"))
    guard case .object(let fields) = try await worker.value else { Issue.record("Missing result"); return }
    #expect(fields["state"] == .string("dismissed"))
    #expect(try await f.repository.projection(identity: f.identity).connections.isEmpty)
}

private actor CapabilityCounter { var calls = 0; func called() { calls += 1 } }
private struct CapabilityReadTool: WorkspaceToolExecuting {
    let enabled: Bool
    let counter: CapabilityCounter
    var definitions: [ChatToolDefinition] { enabled ? [.init(name: "new_read", description: "Read test data", parameters: .object(["type": .string("object"), "properties": .object([:])]))] : [] }
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON { await counter.called(); return .object(["result": .string("real tool result")]) }
}
private actor CapabilityModel: ChatModel {
    var turn = 0
    func events(_ request: ChatModelRequest) -> [ChatModelEvent] {
        defer { turn += 1 }
        if turn == 0 { return [.toolCall(.init(id: "catalog", name: "plugin_catalog", arguments: .object(["query": .string("Notes")]))), .finished(.toolCalls)] }
        if turn == 1 { return [.toolCall(.init(id: "connect", name: "plugin_connect", arguments: .object(["plugin_id": .string("notes"), "reason": .string("Read requested data")]))), .finished(.toolCalls)] }
        if turn == 2 {
            #expect(request.tools.contains { $0.name == "new_read" }, "Newly authorized tools must be visible without another user message")
            return [.toolCall(.init(id: "read", name: "new_read", arguments: .object([:]))), .finished(.toolCalls)]
        }
        return [.text("Done"), .finished(.stop)]
    }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = _Concurrency.Task { for event in await self.events(request) { continuation.yield(event) }; continuation.finish() }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor RequiredSkillModel: ChatModel {
    let create: ChatToolCall
    let ignoresTools: Bool
    private(set) var selected: [String] = []
    init(create: ChatToolCall, ignoresTools: Bool = false) { self.create = create; self.ignoresTools = ignoresTools }
    func events(_ request: ChatModelRequest) -> [ChatModelEvent] {
        if let name = request.requiredTool { selected.append(name) }
        if ignoresTools { return [.text("Saved fake"), .finished(.stop)] }
        switch request.requiredTool {
        case "skill_list": return [.toolCall(.init(id: "list", name: "skill_list", arguments: .object([:]))), .finished(.toolCalls)]
        case "skill_create": return [.toolCall(create), .finished(.toolCalls)]
        default: return [.text("Saved"), .finished(.stop)]
        }
    }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = _Concurrency.Task { for event in await self.events(request) { continuation.yield(event) }; continuation.finish() }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@Test(arguments: [false, true]) func skillCreationRequiresRealCallsInsteadOfModelPromises(ignoresTools: Bool) async throws {
    let f = try await CapabilityFixture(request: "Создай и сохрани навык проверки бюджета. Только сохрани, не запускай его.")
    defer { cleanupWorkspaceTestStorage(f.directory) }
    let projection = try await f.repository.projection(identity: f.identity)
    let source = try #require(projection.messages.first { $0.metadata.id == f.source })
    let configuration = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: f.agent, projection: projection))
    let response = UUID()
    _ = try await WorkspaceResponseRecorder(repository: f.repository, identity: f.identity).begin(id: response, replyingTo: source, agentID: f.agent)
    let model = RequiredSkillModel(create: f.creator, ignoresTools: ignoresTools)
    let runtime = WorkspaceModelRuntime(repository: f.repository, identity: f.identity, pool: .init(), tools: try .init(providers: [WorkspaceSkillTools(repository: f.repository, identity: f.identity)]))
    if ignoresTools {
        await #expect(throws: ChatModelError.invalidStream) {
            try await runtime.generate(source: source, responseID: response, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
                model: model, modelID: "test", configuration: configuration, budgetTokenLimit: 1_000_000, emit: { _ in })
        }
        #expect(try await f.repository.projection(identity: f.identity).skills.isEmpty)
        #expect(try await f.repository.projection(identity: f.identity).messages.filter { $0.role == .assistant }.allSatisfy { !$0.content.contains("Saved fake") })
    } else {
        try await runtime.generate(source: source, responseID: response, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
            model: model, modelID: "test", configuration: configuration, budgetTokenLimit: 1_000_000, emit: { _ in })
        #expect(await model.selected == ["skill_list", "skill_create"])
        #expect(try await f.repository.projection(identity: f.identity).skills.count == 1)
        #expect(try await f.repository.projection(identity: f.identity).tasks.isEmpty)
    }
}

@Test func runtimeResumesOriginalTaskWithFreshToolsAfterConfirmedPluginConnection() async throws {
    // The test adapter declares its synthetic tool; a confirmed connection gates availability.
    let f = try await CapabilityFixture(toolIDs: ["read", "new_read"]); defer { cleanupWorkspaceTestStorage(f.directory) }
    let directory = CapabilityDirectory(fixture: f), counter = CapabilityCounter()
    let refreshing = WorkspaceRefreshingToolProvider(initial: CapabilityReadTool(enabled: false, counter: counter), reload: {
        CapabilityReadTool(enabled: try await directory.isConnected(pluginID: "notes", agentID: f.agent), counter: counter)
    })
    let registry = try WorkspaceToolRegistry(providers: [WorkspacePluginTools(repository: f.repository, identity: f.identity, directory: directory), refreshing], inlineCards: true)
    let projection = try await f.repository.projection(identity: f.identity)
    let source = try #require(projection.messages.first { $0.metadata.id == f.source })
    let configuration = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: f.agent, projection: projection))
    let response = UUID()
    _ = try await WorkspaceResponseRecorder(repository: f.repository, identity: f.identity).begin(id: response, replyingTo: source, agentID: f.agent)
    let worker = _Concurrency.Task {
        try await WorkspaceModelRuntime(repository: f.repository, identity: f.identity, pool: .init(), tools: registry).generate(source: source,
            responseID: response, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64), model: CapabilityModel(),
            modelID: "test", configuration: configuration, budgetTokenLimit: 1_000_000,
            executionToolScope: { $0.subtracting(["forbidden"]) }, emit: { _ in })
    }
    defer { worker.cancel() }
    let card = try await f.pendingCard()
    #expect(await counter.calls == 0)
    try await directory.connect()
    try await WorkspaceConversationCardService(repository: f.repository, identity: f.identity).respond(commandID: UUID(), cardID: card.metadata.id,
        expectedVersion: card.metadata.version, response: .init(action: "connected"))
    try await worker.value
    #expect(await counter.calls == 1)
    #expect(try await f.repository.projection(identity: f.identity).cards.first?.state == "consumed")
}
