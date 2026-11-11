import AppKit
import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation
import Observation
import Synchronization
@testable import Blot

@MainActor private struct ActivityFixture {
    let owner = UUID(), conversation = UUID(), source = UUID(), response = UUID(), agent = UUID(), command = UUID()
    func metadata(_ id: UUID) throws -> BlotV3.RecordMetadata {
        try .init(id: id, ownerId: owner, workspaceId: owner, version: 1, createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date(timeIntervalSince1970: 1000))
    }
    func message(_ id: UUID? = nil, role: BlotV3.MessageRole = .assistant, author: UUID? = nil, commandID: UUID? = nil,
                 content: String = "Проверю документацию.", delivery: BlotV3.DeliveryState = .completed, age: TimeInterval = 0) throws -> BlotV3.Message {
        let id = id ?? response
        return try .init(metadata: .init(id: id, ownerId: owner, workspaceId: owner, version: 1, createdAt: Date(timeIntervalSince1970: 1000 + age), updatedAt: Date(timeIntervalSince1970: 1000 + age)),
            conversationId: conversation, role: role, content: content, delivery: delivery, commandId: commandID ?? command, artifactIds: [], authorAgentId: role == .assistant ? (author ?? agent) : nil)
    }
    func call(_ name: String, _ id: String = "call", arguments: [String: ChatJSON] = [:]) -> ChatToolCall { .init(id: id, name: name, arguments: .object(arguments)) }
    func step(_ calls: [ChatToolCall], results: [String: ChatJSON] = [:], state: BlotV3.ModelStepState = .waiting_tools, index: Int = 0, id: UUID = UUID()) throws -> BlotV3.ModelStep {
        try .init(metadata: metadata(id), conversationId: conversation, sourceMessageId: source, responseMessageId: response,
            executorDeviceId: owner, originDeviceId: owner, executionMode: .local_owned, stepIndex: index, modelId: "compatible", budgetTokenLimit: 20000,
            requestJSON: "secret old context must never become an activity row", toolCallsJSON: String(decoding: try JSONEncoder().encode(calls), as: UTF8.self),
            toolResultsJSON: results.isEmpty ? nil : String(decoding: try JSONEncoder().encode(results), as: UTF8.self), state: state)
    }
    func action(_ tool: String, state: BlotV3.ActionState, scope: WorkspaceToolCallIdentity.Scope = .tool) throws -> BlotV3.PreparedAction {
        try .init(metadata: metadata(WorkspaceToolCallIdentity.actionID(workspaceID: owner, sourceID: source, callID: "call", scope: scope)),
            execution: .init(executorDeviceId: owner, originDeviceId: owner, taskId: UUID(), revision: 1), toolId: tool, resource: "fixture", parameters: "{}", digest: "fixture", consequences: "fixture", expiresAt: Date().addingTimeInterval(600), state: state)
    }
    func snapshot(_ steps: [BlotV3.ModelStep], actions: [BlotV3.PreparedAction] = [], invocations: [BlotV3.ToolInvocation] = []) throws -> WorkspaceSnapshot {
        var value = WorkspaceSnapshot(); value.ownerID = owner; value.localDeviceID = owner
        value.messages = [try message(source, role: .user, content: "Проверь сайт"), try message(content: "", delivery: .running)]
        value.modelSteps = steps; value.preparedActions = actions; value.toolInvocations = invocations
        return value
    }
}

@MainActor private func verifyPresentation() throws {
    let legacyWorkspace = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let legacySource = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    for (scope, expected) in [(WorkspaceToolCallIdentity.Scope.tool, "2F9BC912-6918-8FBA-869F-096D9D1B7967"), (.browser, "66EFBBCC-5765-8417-B38D-660E98802F60"), (.sessionFile, "C0C4A083-94A4-8F99-AAF9-C3839E7BDD5B")] {
        precondition(WorkspaceToolCallIdentity.actionID(workspaceID: legacyWorkspace, sourceID: legacySource, callID: "legacy-call", scope: scope).uuidString == expected)
    }
    print("PASS: persisted tool/browser/session action identity vectors remain compatible")
    let f = ActivityFixture()
    let a = try f.message(), b = try f.message(UUID(), age: 180), c = try f.message(UUID(), author: UUID(), age: 181)
    let user = try f.message(UUID(), role: .user), next = try f.message(UUID(), commandID: UUID())
    precondition(WorkspaceMessageSeries.authorIDs(in: [a, b, c, user, next]) == [a.metadata.id, c.metadata.id, next.metadata.id])
    precondition(WorkspaceMessageSeries.authorIDs(in: [b]) == [b.metadata.id])
    print("PASS: one author across long tool stages; different agent, new request and history boundary restore the author")

    let content = WorkspaceChatPresentation()
    let calls = [f.call("browser_open", arguments: ["url": .string("https://person:secret@example.com/path?token=secret#secret")]), f.call("workspace_read_file", "read", arguments: ["path": .string("Sources/app.swift")])]
    var value = try f.snapshot([f.step(calls)])
    content.update(value, previous: .init())
    let pending = value.messages[1]
    let rows = content.activities(for: pending)
    precondition(rows.count == 2 && rows[0].state == .running && rows[1].state == .queued)
    precondition(content.activityMessageIDs == [f.response])
    let index = WorkspaceMessageIndex(value.messages, activityMessageIDs: content.activityMessageIDs)
    precondition(index.visibleMessages(in: f.conversation).contains { $0.metadata.id == f.response })
    precondition(!rows.flatMap(\.details).contains { $0.value.contains("secret") })
    print("PASS: actual calls show active and queued rows before any assistant text, without URL credentials/query or request context")

    let action = try f.action("browser_click", state: .waiting_approval, scope: .browser)
    let step = try f.step([f.call("browser_click")])
    let previous = value; value = try f.snapshot([step], actions: [action]); content.update(value, previous: previous)
    precondition(content.activities(for: pending).first?.state == .approval)
    let uncertain = try BlotV3.ToolInvocation(metadata: f.metadata(UUID()), execution: action.execution, preparedActionId: action.metadata.id, state: .unknown)
    let before = value; value.toolInvocations = [uncertain]
    let authorsChanged = Mutex(false)
    withObservationTracking { _ = content.agents; _ = content.conversations; _ = content.artifacts } onChange: { authorsChanged.withLock { $0 = true } }
    content.update(value, previous: before)
    precondition(content.activities(for: pending).first?.state == .unknown && !authorsChanged.withLock { $0 })
    let finished = try BlotV3.ToolInvocation(metadata: uncertain.metadata, execution: action.execution, preparedActionId: action.metadata.id, state: .succeeded, result: "{\"state\":\"succeeded\"}")
    let beforeFinished = value; value.toolInvocations = [finished]; content.update(value, previous: beforeFinished)
    precondition(content.activities(for: pending).first?.state == .succeeded)
    print("PASS: exact browser action tracks approval → unknown → reconciled success without invalidating message identity")

    let denied = try f.action("workspace_write_file", state: .denied, scope: .sessionFile)
    let deniedSnapshot = try f.snapshot([f.step([f.call("workspace_write_file")])], actions: [denied])
    content.update(deniedSnapshot, previous: value)
    precondition(content.activities(for: pending).first?.state == .denied)
    let builder = WorkspaceToolActivityBuilder()
    for (state, expected) in [(BlotV3.ModelStepState.canceled, WorkspaceToolActivity.State.stopped), (.interrupted, .unknown), (.completed, .unknown)] {
        let terminalStep = try f.step([f.call("git_push")], state: state)
        precondition(builder.build(steps: [terminalStep], actions: [:], invocations: [:], connections: []).rows.first?.state == expected)
    }
    let failure: ChatJSON = .object(["isError": .bool(true)])
    let failedStep = try f.step([f.call("browser_click")], results: ["call": failure], state: .completed)
    precondition(builder.build(steps: [failedStep], actions: [:], invocations: [:], connections: []).rows.first?.state == .failed)
    let pluginName = AppleToolCatalog.all.first { $0.plugin == .reminders && $0.operation == "create" }!.definition.name
    let pluginRow = builder.build(steps: [try f.step([f.call(pluginName)], results: ["call": .object(["state": .string("succeeded")])])], actions: [:], invocations: [:], connections: []).rows.first!
    precondition(pluginRow.plugin?.entry.appleID == .reminders)
    print("PASS: denial, cancellation, missing result and failed provider output never become success; app calls retain native full-color plugin identity")

    let secretCall = f.call("browser_type", arguments: ["text": .string("secret")])
    let privateRow = builder.build(steps: [try f.step([secretCall], results: ["call": .object(["cookies": .string("secret"), "password": .string("secret")])])], actions: [:], invocations: [:], connections: []).rows.first!
    precondition(privateRow.details.isEmpty)
    let process = f.call("process_run", arguments: ["executable": .string("/bin/zsh"), "arguments": .array([.string("secret")]), "variables": .array([.string("TOKEN=secret")])])
    let processRow = builder.build(steps: [try f.step([process], results: ["call": .object(["state": .string("running"), "stdout": .string(String(repeating: "x", count: 9000))])])], actions: [:], invocations: [:], connections: []).rows.first!
    precondition(processRow.state == .running && processRow.details.allSatisfy { !$0.value.contains("secret") && $0.value.count <= 3000 })
    precondition(processRow.details.contains { $0.label == "Журнал / Log" })
    let poll = f.call("process_status", "poll", arguments: ["process_id": .string("process")])
    let polls = [try f.step([poll], results: ["poll": .object(["state": .string("running")])], index: 0), try f.step([poll], results: ["poll": .object(["state": .string("succeeded"), "exitCode": .number(2)])], index: 1)]
    let latest = builder.build(steps: polls, actions: [:], invocations: [:], connections: []).rows
    precondition(latest.count == 1 && latest[0].state == .failed)
    print("PASS: bounded stdout/stderr, explicit truncation, no arbitrary parameters or plugin payloads, repeated process checks collapse and nonzero exit is failure")

    let baseline = ContinuousClock.now
    for _ in 0..<5000 { _ = content.activities(for: pending) }
    print("CACHE: 5000 activity lookups: \(baseline.duration(to: .now))")
}

private struct ProgressModel: ChatModel {
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { output in
            if request.messages.contains(where: { $0.role == "tool" && $0.name == "document_create" }) {
                output.yield(.text("Документ готов.")); output.yield(.finished(.stop))
            } else {
                output.yield(.text("Подготовлю документ, затем проверю результат."))
                output.yield(.toolCall(.init(id: "document", name: "document_create", arguments: .object(["name": .string("progress-result.md"), "format": .string("markdown"), "content": .string("Verified result")]))))
                output.yield(.finished(.toolCalls))
            }
            output.finish()
        }
    }
}

@MainActor @main enum AgentProgressVerification {
    static func main() async throws {
        try verifyPresentation()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blot-progress-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalWorkspaceService(databaseURL: root.appendingPathComponent("workspace.sqlite"), makeModel: { _ in ProgressModel() })
        let store = WorkspaceStore(mode: .live, service: local)
        await store.loadWorkspace()
        store.form.agent = WorkspaceAgentForm(name: "Progress fixture", instructions: "Create a requested document", toolIDs: ["document_create"])
        await store.perform(.createAgent)
        guard let agent = store.selectedAgentID else { throw VoiceFailure.emptyResponse }
        await store.newChat(with: agent)
        store.form.composer.draft = "Создай документ"
        await store.perform(.send)
        for _ in 0..<300 {
            if !store.isReplying { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        let replies = store.currentVisibleMessages.filter { $0.role == .assistant }
        precondition(replies.count == 2 && replies[0].content.contains("Подготовлю") && replies[1].content == "Документ готов.")
        precondition(WorkspaceMessageSeries.authorIDs(in: replies).count == 1)
        precondition(store.chatContent.activities(for: replies[0]).first?.state == .succeeded)
        precondition(store.chatContent.activities(for: replies[1]).isEmpty)
        precondition(!store.snapshot.artifacts.isEmpty)
        print("PASS: actual chat → separate progress bubble → real document tool and recorded activity → separate final bubble; one author")
        let saved = try await local.currentSnapshot()
        let presentation = WorkspaceChatPresentation(); presentation.update(saved, previous: .init())
        precondition(presentation.activities(for: replies[0]).first?.state == .succeeded)
        print("PASS: restored snapshot reconstructs tool activity without rerunning the model or operation")
        try await local.close()
    }
}
