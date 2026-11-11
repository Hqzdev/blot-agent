import BlotDomain
import BlotWorkspace
import Foundation
import Testing
@testable import BlotAppleIntegrations

@Test func planCompletionRequiresTheRequestedOperationsFromEveryNamedApp() {
    let scope = AppleTaskToolScope()
    #expect(scope.requiredTools(task: "создай напоминание и контакт, email qa@example.invalid", discoveryOnly: false)
        == ["apple_reminders_create", "apple_contacts_create"])
    #expect(scope.requiredTools(task: "проверь Calendar и Reminders", discoveryOnly: true)
        == ["apple_calendar_resources", "apple_reminders_resources"])
    #expect(scope.requiredTools(task: "предложи тему короткого письма", discoveryOnly: false).isEmpty)
    #expect(scope.requiredTools(task: "создай черновик письма. Не отправляй.", discoveryOnly: false) == ["apple_mail_create"])
    #expect(scope.requiredTools(task: "создай контакт, если есть доступ", discoveryOnly: false) == ["apple_contacts_create"])
}

@Test func delegatedBriefDoesNotExposeOtherMembersAppleApps() {
    let assigned = Set(AppleToolCatalog.all.map { $0.definition.name }).union(["file_read", "document_create"])
    let scope = AppleTaskToolScope().toolIDs(task: "создай напоминание и тестовый контакт, email qa@example.invalid", assigned: assigned)
    #expect(scope.contains("apple_reminders_create") && scope.contains("apple_contacts_create"))
    #expect(!scope.contains("apple_calendar_create") && !scope.contains("apple_mail_create"))
    #expect(scope.contains("file_read"))
    let mira = AppleTaskToolScope().toolIDs(task: "создай заметку и файл. Не отправлять письма.", assigned: assigned)
    #expect(mira.contains("apple_notes_create") && mira.contains("apple_files_create"))
    #expect(!mira.contains("apple_mail_create"))
    #expect(AppleTaskToolScope().toolIDs(task: "проанализируй данные", assigned: ["file_read"]) == ["file_read"])
}

@Test func listPagesPreserveIDsBoundPreviewsAndExposeRemainingMatches() throws {
    let page = try AppleListPage(AppleArguments(.object(["limit": .string("2"), "offset": .string("4")])))
    let value = page.result([["id-1", String(repeating: "a", count: 1000)], ["id-2", "second"], ["id-3", "third"]], names: ["id", "title"])
    guard case .object(let fields) = value, case .array(let items) = fields["items"] else { Issue.record("Expected metadata page"); return }
    #expect(items.count == 2 && fields["has_more"] == .bool(true) && fields["next_offset"] == .string("6"))
    #expect(items[0] == appleObject(["id": "id-1", "title": String(repeating: "a", count: 256)]))
    #expect(page.result([], names: ["id"]) == .object(["items": .array([]), "has_more": .bool(false), "next_offset": .null]))
    for fields in [["limit": "0"], ["limit": "51"], ["offset": "-1"], ["offset": "text"]] {
        #expect(throws: AppleIntegrationError.self) { try AppleListPage(AppleArguments(appleObject(fields))) }
    }
}

@MainActor
private final class TestAppleExecutor: AppleIntegrationExecuting {
    let interactions = AppleInteractionCenter()
    var permitted = true
    var count = 0
    var fail = false
    func resources(_ plugin: ApplePluginID, selected: [String]) async throws -> [AppleResource] { selected.map { .init(id: $0, name: $0) } }
    func accessible(_ plugin: ApplePluginID, resources: [String]) async -> Bool { permitted }
    func preview(_ tool: AppleTool, arguments: ChatJSON) async throws -> ChatJSON? { nil }
    func execute(_ tool: AppleTool, arguments: ChatJSON) async throws -> ChatJSON {
        count += 1
        if fail { throw AppleIntegrationError.uncertainResult }
        return appleObject(["id": "created"])
    }
}

private struct TestWorkspace {
    let directory: URL
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let agent: UUID
    let source: UUID
    let connection: UUID
    static func make(content: String = "Create event") async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = try WorkspaceRepository(url: directory.appendingPathComponent("workspace.sqlite"))
        let identity = try await repository.localIdentity()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Agent", instructions: "Use selected calendars"))
        let connection = try await WorkspaceConnectionService(repository: repository, identity: identity).save(pluginID: "apple.calendar", name: "Календарь",
            resources: ["selected"], agentIDs: [agent], toolIDs: AppleToolCatalog.tools(for: .calendar).map { $0.definition.name })
        let chat = WorkspaceChatService(repository: repository, identity: identity)
        let conversation = try await chat.createConversation(commandID: UUID(), title: "Test", agentID: agent)
        let source = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: content)
        return .init(directory: directory, repository: repository, identity: identity, agent: agent, source: source, connection: connection)
    }
    var context: WorkspaceToolContext {
        .init(sourceMessageID: source, taskID: nil, allowedToolIDs: Set(AppleToolCatalog.tools(for: .calendar).map { $0.definition.name }), agentID: agent)
    }
    func close() async throws { try await repository.close(); try FileManager.default.removeItem(at: directory) }
    func createCall(resource: String = "selected", id: String = "one") -> ChatToolCall {
        .init(id: id, name: "apple_calendar_create", arguments: appleObject(["resource_id": resource, "title": "Meeting",
            "start": "2026-11-05T10:00:00Z", "end": "2026-11-05T11:00:00Z"]))
    }
}

@MainActor @Test func selectedResourcesAndAssignmentsAreEnforcedAtExecution() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    let denied = try await provider.execute(workspace.createCall(resource: "outside"), context: workspace.context)
    #expect(denied != appleObject(["id": "created"]))
    #expect(executor.count == 0)
    let stranger = WorkspaceToolContext(sourceMessageID: workspace.source, taskID: nil, allowedToolIDs: workspace.context.allowedToolIDs, agentID: UUID())
    #expect(try await provider.availableDefinitions(context: stranger).isEmpty)
    try await workspace.close()
}

@MainActor @Test func discoveryDoesNotExpandSchemasForAnotherTurnOrGroupMember() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    #expect(try await provider.availableDefinitions(context: workspace.context).map(\.name) == ["apple_calendar_resources"])
    _ = try await provider.execute(.init(id: "discover", name: "apple_calendar_resources", arguments: .object([:])), context: workspace.context)
    #expect(try await provider.availableDefinitions(context: workspace.context).contains { $0.name == "apple_calendar_create" })
    let original = try #require(try await workspace.repository.record(BlotV3.Message.self, id: workspace.source, workspaceID: workspace.identity.workspaceID))
    let nextID = try await WorkspaceChatService(repository: workspace.repository, identity: workspace.identity).sendMessage(commandID: UUID(), conversationID: original.conversationId, content: "Next task")
    let anotherTurn = WorkspaceToolContext(sourceMessageID: nextID, taskID: nil,
        allowedToolIDs: workspace.context.allowedToolIDs, agentID: workspace.agent)
    #expect(try await provider.availableDefinitions(context: anotherTurn).map(\.name) == ["apple_calendar_resources"])
    let colleague = try await WorkspaceAgentService(repository: workspace.repository, identity: workspace.identity).save(commandID: UUID(), draft: .init(name: "Colleague", instructions: "Help"))
    try await WorkspaceConnectionService(repository: workspace.repository, identity: workspace.identity).save(pluginID: "apple.calendar", name: "Calendar", resources: ["selected"],
        agentIDs: [workspace.agent, colleague], toolIDs: Array(workspace.context.allowedToolIDs))
    let anotherMember = WorkspaceToolContext(sourceMessageID: workspace.source, taskID: nil,
        allowedToolIDs: workspace.context.allowedToolIDs, agentID: colleague)
    #expect(try await provider.availableDefinitions(context: anotherMember).map(\.name) == ["apple_calendar_resources"])
    try await workspace.close()
}

@MainActor @Test func discoveryOnlyRequestCannotReadContentOrWriteEvenIfModelCallsHiddenTools() async throws {
    let workspace = try await TestWorkspace.make(content: "Только обнаружение ресурсов. Ничего не создавать и не менять."), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    _ = try await provider.execute(.init(id: "resources", name: "apple_calendar_resources", arguments: .object([:])), context: workspace.context)
    #expect(try await provider.availableDefinitions(context: workspace.context).map(\.name) == ["apple_calendar_resources"])
    _ = try await provider.execute(workspace.createCall(), context: workspace.context)
    _ = try await provider.execute(.init(id: "list", name: "apple_calendar_list", arguments: appleObject(["resource_id": "selected", "start": "2026-11-07T00:00:00Z", "end": "2026-11-08T00:00:00Z"])), context: workspace.context)
    #expect(executor.count == 0)
    #expect(try await workspace.repository.projection(identity: workspace.identity).actions.isEmpty)
    try await workspace.close()
}

@MainActor @Test func ordinaryWriteIsDurableAndReplayedCallDoesNotCreateTwice() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    let first = try await provider.execute(workspace.createCall(), context: workspace.context)
    #expect(first == appleObject(["id": "created"]))
    #expect(try await provider.execute(workspace.createCall(), context: workspace.context) == first)
    #expect(executor.count == 1)
    let projection = try await workspace.repository.projection(identity: workspace.identity)
    #expect(projection.actions.count == 1 && projection.actions[0].state == .succeeded)
    #expect(projection.invocations.count == 1 && projection.invocations[0].state == .succeeded)
    try await workspace.close()
}

@MainActor @Test func revokedSystemAccessAndDisconnectedPluginImmediatelyRemoveTools() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    #expect(try await !provider.availableDefinitions(context: workspace.context).isEmpty)
    executor.permitted = false
    #expect(try await provider.availableDefinitions(context: workspace.context).isEmpty)
    _ = try await provider.execute(workspace.createCall(), context: workspace.context)
    #expect(executor.count == 0)
    executor.permitted = true
    try await WorkspaceConnectionService(repository: workspace.repository, identity: workspace.identity).disconnect(workspace.connection)
    #expect(try await provider.availableDefinitions(context: workspace.context).isEmpty)
    _ = try await provider.execute(workspace.createCall(), context: workspace.context)
    #expect(executor.count == 0)
    try await workspace.close()
}

@MainActor @Test func unknownExternalOutcomeIsNeverRetried() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    executor.fail = true
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    _ = try await provider.execute(workspace.createCall(), context: workspace.context)
    executor.fail = false
    _ = try await provider.execute(workspace.createCall(), context: workspace.context)
    #expect(executor.count == 1)
    #expect(try await workspace.repository.projection(identity: workspace.identity).invocations.first?.state == .unknown)
    try await workspace.close()
}

@MainActor @Test func deleteWaitsForUserAndRefusalDoesNotExecute() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    let call = ChatToolCall(id: "delete", name: "apple_calendar_delete", arguments: appleObject(["resource_id": "selected", "id": "existing"]))
    let task = _Concurrency.Task { try await provider.execute(call, context: workspace.context) }
    for _ in 0..<1000 {
        if executor.interactions.pending != nil { break }
        try await _Concurrency.Task.sleep(for: .milliseconds(2))
    }
    let pending = try #require(executor.interactions.pending)
    #expect(executor.count == 0)
    executor.interactions.finish(pending.id, result: .success(.bool(false)))
    _ = try await task.value
    #expect(executor.count == 0)
    #expect(try await workspace.repository.projection(identity: workspace.identity).actions.first?.state == .denied)
    try await workspace.close()
}

@MainActor @Test func relativeFilesCannotEscapeRootOrFollowAnOutsideSymlink() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = directory.appendingPathComponent("root"), outside = directory.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
    #expect(throws: AppleIntegrationError.self) { try AppleFolderStore.containedURL(root: root, path: "../outside") }
    #expect(throws: AppleIntegrationError.self) { try AppleFolderStore.containedURL(root: root, path: "/etc/passwd") }
    #expect(throws: AppleIntegrationError.self) { try AppleFolderStore.containedURL(root: root, path: "link/secret") }
    #expect(try AppleFolderStore.containedURL(root: root, path: "note.txt").lastPathComponent == "note.txt")
}

#if os(macOS)
@MainActor @Test func automationDoesNotLaunchClosedAppsEvenWhenAccessIsRequested() async throws {
    let automation = AppleAutomation(running: { _ in false })
    #expect(throws: AppleIntegrationError.self) { try automation.requireRunning(.shortcuts) }
    for plugin in [ApplePluginID.mail, .notes] {
        #expect(await automation.authorized(plugin) == false)
        #expect(await automation.authorized(plugin, request: true) == false)
        await #expect(throws: AppleIntegrationError.self) { _ = try await automation.resources(plugin) }
    }
    #expect(throws: AppleIntegrationError.self) { try automation.compileScripts() }
}
@MainActor @Test func fixedAppleScriptsCompileOnlyIfBothAppsAreAlreadyRunning() throws {
    let automation = AppleAutomation()
    guard automation.isRunning(.notes), automation.isRunning(.mail) else { return }
    try automation.compileScripts()
}
#endif

@Test func legacyConnectionsDecodeWithoutAppleFields() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/v3/Connection.json")
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    for key in ["pluginId", "resourceIds", "agentIds", "allowedOperations"] { object.removeValue(forKey: key) }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let value = try decoder.decode(BlotV3.Connection.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(value.pluginId == nil && value.resourceIds == nil && value.agentIds == nil)
}

@MainActor @Test func disconnectWhileConfirmationIsOpenPreventsExecution() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    let call = ChatToolCall(id: "delete", name: "apple_calendar_delete", arguments: appleObject(["resource_id": "selected", "id": "existing"]))
    let task = _Concurrency.Task { try await provider.execute(call, context: workspace.context) }
    for _ in 0..<1000 {
        if executor.interactions.pending != nil { break }
        try await _Concurrency.Task.sleep(for: .milliseconds(2))
    }
    let pending = try #require(executor.interactions.pending)
    try await WorkspaceConnectionService(repository: workspace.repository, identity: workspace.identity).disconnect(workspace.connection)
    executor.interactions.finish(pending.id, result: .success(.bool(true)))
    _ = try await task.value
    #expect(executor.count == 0)
    try await workspace.close()
}

@MainActor @Test func reusedCallIDWithChangedArgumentsDoesNotReplayUnrelatedResult() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    _ = try await provider.execute(workspace.createCall(), context: workspace.context)
    let changed = ChatToolCall(id: "one", name: "apple_calendar_create", arguments: appleObject(["resource_id": "selected", "title": "Other",
        "start": "2026-11-05T10:00:00Z", "end": "2026-11-05T11:00:00Z"]))
    let result = try await provider.execute(changed, context: workspace.context)
    #expect(result != appleObject(["id": "created"]))
    #expect(executor.count == 1)
    try await workspace.close()
}

@MainActor @Test func resourceDiscoveryExpandsOnlyTheRequestedApplicationSchemas() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    let initial = try await provider.availableDefinitions(context: workspace.context).map(\.name)
    #expect(initial == ["apple_calendar_resources"])
    _ = try await provider.execute(.init(id: "resources", name: "apple_calendar_resources", arguments: .object([:])), context: workspace.context)
    let expanded = try await provider.availableDefinitions(context: workspace.context).map(\.name)
    #expect(expanded.contains("apple_calendar_create"))
    #expect(expanded.allSatisfy { $0.hasPrefix("apple_calendar_") })
    #expect(executor.count == 0)
    try await workspace.close()
}

private actor AppleFlowModel: ChatModel {
    private(set) var requests: [ChatModelRequest] = []
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                let turn = await record(request)
                if turn == 1 {
                    continuation.yield(.toolCall(.init(id: "discover", name: "apple_calendar_resources", arguments: .object([:]))))
                } else if turn == 2 {
                    continuation.yield(.toolCall(.init(id: "create", name: "apple_calendar_create", arguments: appleObject([
                        "resource_id": "selected", "title": "Meeting", "start": "2026-11-05T10:00:00Z", "end": "2026-11-05T11:00:00Z"]))))
                } else { continuation.yield(.text("Created")) }
                continuation.yield(.usage(try! .init(inputTokens: 10, outputTokens: 5)))
                continuation.yield(.finished(turn < 3 ? .toolCalls : .stop))
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
    private func record(_ request: ChatModelRequest) -> Int { requests.append(request); return requests.count }
}

@MainActor @Test func modelRuntimeDiscoversAppleToolsExecutesAndContinuesFromDurableResult() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor(), model = AppleFlowModel()
    let projection = try await workspace.repository.projection(identity: workspace.identity)
    let configuration = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: workspace.agent, projection: projection))
    let source = try #require(projection.messages.first { $0.metadata.id == workspace.source })
    let responseID = UUID()
    _ = try await WorkspaceResponseRecorder(repository: workspace.repository, identity: workspace.identity).begin(id: responseID, replyingTo: source, agentID: workspace.agent)
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    let runtime = WorkspaceModelRuntime(repository: workspace.repository, identity: workspace.identity, pool: .init(), tools: try .init(providers: [provider]))
    try await runtime.generate(source: source, responseID: responseID, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
        model: model, modelID: "test", configuration: configuration, budgetTokenLimit: 100000, emit: { _ in })
    let requests = await model.requests
    #expect(requests.count == 3)
    #expect(requests[0].tools.map(\.name) == ["apple_calendar_resources"])
    #expect(requests[1].tools.contains { $0.name == "apple_calendar_create" })
    #expect(requests[2].messages.last?.role == "tool")
    #expect(executor.count == 1)
    let completed = try await workspace.repository.projection(identity: workspace.identity)
    #expect(completed.tasks.first?.state == .completed)
    #expect(completed.invocations.first?.state == .succeeded)
    let restored = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    let restoredTools = try await restored.availableDefinitions(context: workspace.context)
    #expect(restoredTools.contains { $0.name == "apple_calendar_create" })
    let nextSource = try await WorkspaceChatService(repository: workspace.repository, identity: workspace.identity).sendMessage(commandID: UUID(), conversationID: source.conversationId, content: "Another task")
    let nextTools = try await restored.availableDefinitions(context: .init(sourceMessageID: nextSource, taskID: nil,
        allowedToolIDs: workspace.context.allowedToolIDs, agentID: workspace.agent))
    #expect(nextTools.map(\.name) == ["apple_calendar_resources"])
    #expect(executor.count == 1)
    try await workspace.close()
}

@MainActor @Test func unknownOutcomeBlocksNewCallIDsUntilExplicitUserResolution() async throws {
    let workspace = try await TestWorkspace.make(), executor = TestAppleExecutor()
    executor.fail = true
    let provider = AppleToolProvider(repository: workspace.repository, identity: workspace.identity, controller: executor)
    _ = try await provider.execute(workspace.createCall(id: "first"), context: workspace.context)
    executor.fail = false
    _ = try await provider.execute(workspace.createCall(id: "different"), context: workspace.context)
    #expect(executor.count == 1)
    let projection = try await workspace.repository.projection(identity: workspace.identity)
    let pending = try #require(AppleInvocationRecovery.pending(plugin: .calendar, deviceID: workspace.identity.deviceID, actions: projection.actions, invocations: projection.invocations).first)
    try await WorkspacePermissionService(repository: workspace.repository, identity: workspace.identity).finish(commandID: UUID(), invocationID: pending.id,
        state: .failed, result: #"{"state":"verified_by_user","succeeded":false}"#)
    let result = try await provider.execute(workspace.createCall(id: "new-user-request"), context: workspace.context)
    #expect(result == appleObject(["id": "created"]))
    #expect(executor.count == 2)
    try await workspace.close()
}
