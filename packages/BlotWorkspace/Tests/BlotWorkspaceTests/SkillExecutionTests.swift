import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct SkillFixture: Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let agent: UUID
    let chat: UUID
    init() async throws {
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("skills.sqlite"))
        identity = try await repository.localIdentity()
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Worker", instructions: "Work concisely", toolIDs: ["read", "write"]))
        chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Skills", agentID: agent)
    }
    var skills: WorkspaceSkillService { .init(repository: repository, identity: identity) }
    var assignments: WorkspaceSkillAssignmentService { .init(repository: repository, identity: identity) }
    var runner: WorkspaceSkillRunService { .init(repository: repository, identity: identity) }
    func create(tools: [String] = ["read"]) async throws -> BlotV3.Skill {
        let id = try await skills.save(commandID: UUID(), name: "Brief", instructions: "Summarize {{topic}}. {{note}}",
            parameters: [.init(name: "topic"), .init(name: "note", required: false)], toolIDs: tools)
        return try #require(try await repository.record(BlotV3.Skill.self, id: id, workspaceID: identity.workspaceID))
    }
    func assign(_ skill: BlotV3.Skill) async throws {
        try await assignments.set(commandID: UUID(), skillID: skill.metadata.id, agentID: agent, assigned: true, expectedVersion: 0)
    }
}

private actor SkillModel: ChatModel {
    private(set) var requests: [ChatModelRequest] = []
    let beforeReply: (@Sendable () async throws -> Void)?
    init(beforeReply: (@Sendable () async throws -> Void)? = nil) { self.beforeReply = beforeReply }
    func respond(_ request: ChatModelRequest) async throws {
        requests.append(request); try await beforeReply?()
    }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                do { try await self.respond(request); continuation.yield(.text("Done.")); continuation.yield(.finished(.stop)); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
private struct SkillTestTools: WorkspaceToolExecuting {
    var definitions: [ChatToolDefinition] { ["read", "write"].map { .init(name: $0, description: $0, parameters: .object(["type": .string("object"), "properties": .object([:])])) } }
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON { .object(["ok": .bool(true)]) }
}

@Test func skillLaunchPinsRevisionValuesAndRestrictedToolsAcrossEditsAndReload() async throws {
    let f = try await SkillFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let skill = try await f.create(); try await f.assign(skill)
    let command = UUID()
    let id = try await f.runner.run(commandID: command, skillID: skill.metadata.id, agentID: f.agent, values: ["topic": "Revenue"], conversationID: f.chat)
    #expect(try await f.runner.run(commandID: command, skillID: skill.metadata.id, agentID: f.agent, values: ["topic": "Revenue"], conversationID: f.chat) == id)
    _ = try await f.skills.save(commandID: UUID(), skillID: skill.metadata.id, expectedVersion: 1, name: "New brief", instructions: "Different routine", parameters: [], toolIDs: ["write"])
    let reopened = try await workspaceTestRepository(url: f.directory.appendingPathComponent("skills.sqlite"))
    let projection = try await reopened.projection(identity: f.identity)
    let task = try #require(projection.tasks.first)
    #expect(task.goal == "Summarize Revenue. " && task.skillRevisionId == skill.activeRevisionId && projection.tasks.count == 1)
    let model = SkillModel()
    try await WorkspaceTaskExecution(repository: reopened, identity: f.identity, pool: .init(), tools: .init(providers: [SkillTestTools()]), maximumOutputTokens: 64).run(taskID: id, model: model)
    let request = try #require(await model.requests.first)
    #expect(request.tools.map(\.name) == ["read"])
    #expect(request.messages.contains { $0.content == task.goal })
    #expect(try await reopened.record(BlotV3.Task.self, id: id, workspaceID: f.identity.workspaceID)?.state == .completed)
}

@Test func skillAssignmentDoesNotGrantToolsAndInvalidLaunchIsAtomic() async throws {
    let f = try await SkillFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let skill = try await f.create(tools: ["unavailable"])
    await #expect(throws: WorkspaceSkillError.notAssigned) { _ = try await f.runner.run(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, values: ["topic": "X"]) }
    try await f.assign(skill)
    await #expect(throws: WorkspaceSkillError.toolsUnavailable) { _ = try await f.runner.run(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, values: ["topic": "X"]) }
    #expect(try await f.repository.projection(identity: f.identity).tasks.isEmpty)
    #expect(try await f.repository.projection(identity: f.identity).configurations.first?.toolIds == ["read", "write"])
}

@Test func skillMissingValuesWrongChatAndForeignRevisionCannotEnqueue() async throws {
    let f = try await SkillFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let skill = try await f.create(); try await f.assign(skill)
    let other = try await f.create()
    await #expect(throws: WorkspaceSkillError.revisionUnavailable) { _ = try await f.runner.run(commandID: UUID(), skillID: skill.metadata.id, revisionID: other.activeRevisionId, agentID: f.agent, values: ["topic": "X"]) }
    await #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try await f.runner.run(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, values: [:]) }
    let group = try await WorkspaceGroupService(repository: f.repository, identity: f.identity).create(commandID: UUID(), title: "Other group", agentIDs: [f.agent])
    try await WorkspaceGroupService(repository: f.repository, identity: f.identity).setAgent(commandID: UUID(), conversationID: group, agentID: f.agent, removed: true)
    await #expect(throws: WorkspaceSkillError.wrongConversation) { _ = try await f.runner.run(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, values: ["topic": "X"], conversationID: group) }
    #expect(try await f.repository.projection(identity: f.identity).tasks.isEmpty)
}

@Test func skillArchiveAndRevocationStopQueuedAndInFlightExecution() async throws {
    let f = try await SkillFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let skill = try await f.create(); try await f.assign(skill)
    let id = try await f.runner.run(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, values: ["topic": "X"])
    let model = SkillModel { try await f.assignments.set(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, assigned: false, expectedVersion: 1) }
    await #expect(throws: WorkspaceSkillError.notAssigned) {
        try await WorkspaceTaskExecution(repository: f.repository, identity: f.identity, pool: .init(), tools: .init(providers: [SkillTestTools()]), maximumOutputTokens: 64).run(taskID: id, model: model)
    }
    #expect(try await f.repository.record(BlotV3.Task.self, id: id, workspaceID: f.identity.workspaceID)?.state == .failed)
    try await f.skills.setArchived(commandID: UUID(), skillID: skill.metadata.id, expectedVersion: 1, archived: true)
    await #expect(throws: WorkspaceSkillError.archived) { _ = try await f.runner.run(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, values: ["topic": "X"]) }
}

@Test func skillHistoryRestoresExactRevisionAndValidatesTemplates() async throws {
    let f = try await SkillFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let skill = try await f.create()
    _ = try await f.skills.save(commandID: UUID(), skillID: skill.metadata.id, expectedVersion: 1, name: "Brief", instructions: "Second", parameters: [], toolIDs: [])
    try await f.skills.activate(commandID: UUID(), skillID: skill.metadata.id, expectedVersion: 2, revisionID: skill.activeRevisionId)
    let projection = try await f.repository.projection(identity: f.identity)
    #expect(projection.skills.first?.activeRevisionId == skill.activeRevisionId && projection.skillRevisions.count == 2)
    await #expect(throws: WorkspaceStorageError.versionConflict) { try await f.skills.setArchived(commandID: UUID(), skillID: skill.metadata.id, expectedVersion: 1, archived: true) }
    for template in ["{{unknown}}", "{{topic", "topic}}", "{{ topic }}"] {
        await #expect(throws: WorkspaceSkillError.invalidTemplate) { _ = try await f.skills.save(commandID: UUID(), name: "Broken", instructions: template, parameters: [.init(name: "topic")], toolIDs: []) }
    }
}

@Test func skillToolsDiscoverOnlyAssignmentsAndCannotRecursivelyQueueFromTasks() async throws {
    let f = try await SkillFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let skill = try await f.create(); try await f.assign(skill)
    _ = try await f.create()
    let source = try await WorkspaceChatService(repository: f.repository, identity: f.identity).sendMessage(commandID: UUID(), conversationID: f.chat, content: "Run Brief")
    let provider = WorkspaceSkillTools(repository: f.repository, identity: f.identity)
    let context = WorkspaceToolContext(sourceMessageID: source, taskID: nil, allowedToolIDs: ["skill_list", "skill_run"], agentID: f.agent)
    let list = try await provider.execute(.init(id: "list", name: "skill_list", arguments: .object([:])), context: context)
    guard case .object(let fields) = list, case .array(let items) = fields["skills"] else { Issue.record("Missing skills"); return }
    #expect(items.count == 1)
    let call = ChatToolCall(id: "run", name: "skill_run", arguments: .object(["skill_id": .string(skill.metadata.id.uuidString), "values": .array([.object(["name": .string("topic"), "value": .string("X")])])]))
    _ = try await provider.execute(call, context: context)
    _ = try await provider.execute(call, context: context)
    #expect(try await f.repository.projection(identity: f.identity).tasks.count == 1)
    let nested = WorkspaceToolContext(sourceMessageID: source, taskID: UUID(), allowedToolIDs: context.allowedToolIDs, agentID: f.agent)
    #expect(try await provider.availableDefinitions(context: nested).isEmpty)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await provider.execute(call, context: nested) }
}

@Test func skillSchedulePinsRevisionAndFailsAfterUnassignment() async throws {
    let f = try await SkillFixture(); defer { cleanupWorkspaceTestStorage(f.directory) }
    let skill = try await f.create(); try await f.assign(skill)
    let service = WorkspaceScheduleService(repository: f.repository, identity: f.identity)
    let schedule = try await service.save(commandID: UUID(), draft: .init(name: "Brief", goal: "Summarize X", agentID: f.agent,
        executorDeviceID: f.identity.deviceID, timezone: "UTC", localTime: "12:00", weekdays: [1,2,3,4,5,6,7], skillRevisionID: skill.activeRevisionId))
    let task = try await service.runManually(commandID: UUID(), scheduleID: schedule)
    #expect(try await f.repository.record(BlotV3.Task.self, id: task, workspaceID: f.identity.workspaceID)?.skillRevisionId == skill.activeRevisionId)
    try await f.assignments.set(commandID: UUID(), skillID: skill.metadata.id, agentID: f.agent, assigned: false, expectedVersion: 1)
    await #expect(throws: WorkspaceSkillError.notAssigned) { _ = try await service.runManually(commandID: UUID(), scheduleID: schedule) }
    #expect(try await f.repository.projection(identity: f.identity).automationRuns.count == 1)
}
