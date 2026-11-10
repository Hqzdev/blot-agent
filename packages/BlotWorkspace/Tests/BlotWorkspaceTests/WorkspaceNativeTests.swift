#if os(macOS)
import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor NativeTestCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}

private struct NativeWorkspaceFixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let credentials = NativeTestCredentials()
    let service: WorkspaceNativeService
    let agent: UUID
    let conversation: UUID
    let source: UUID
    let project: UUID
    init() async throws {
        repository = try await workspaceTestRepository(url: folder.appendingPathComponent("workspace.sqlite")); identity = try await repository.localIdentity()
        let code = folder.appendingPathComponent("code")
        try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)
        try Data("before".utf8).write(to: code.appendingPathComponent("a.txt"))
        let files = WorkspaceFileService(repository: repository, identity: identity, directory: folder.appendingPathComponent("attachments"))
        service = WorkspaceNativeService(repository: repository, identity: identity, credentials: credentials, files: files, makeExecutor: { NativeExecutor() })
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Engineer", instructions: "Use approved tools"))
        conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Code", agentID: agent)
        source = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: conversation, content: "Work on this project")
        project = try await service.connect(name: "Code", root: code, bookmark: nil, agents: [agent], trustedCLI: true)
        try await service.select(projectID: project, conversationID: conversation)
    }
    var context: WorkspaceToolContext { .init(sourceMessageID: source, taskID: nil, allowedToolIDs: Set(WorkspaceNativeCatalog.toolIDs), agentID: agent) }
    func tools(_ confirm: @escaping @Sendable (String, String) async throws -> Bool = { _, _ in true }) -> WorkspaceNativeTools {
        .init(service: service, repository: repository, identity: identity, confirm: confirm)
    }
}

@Test func nativeWorkspaceWritesNeedApprovalAndRejectStaleContentWithoutOverwriting() async throws {
    let f = try await NativeWorkspaceFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let read = try await f.tools().execute(.init(id: "read", name: "project_read_file", arguments: .object(["path": .string("a.txt")])), context: f.context)
    let hash = try #require(read.mcpFields["sha256"]?.mcpString)
    let args: ChatJSON = .object(["path": .string("a.txt"), "content": .string("agent"), "expected_hash": .string(hash)])
    let denied = try await f.tools { _, _ in false }.execute(.init(id: "denied", name: "project_write_file", arguments: args), context: f.context)
    #expect(denied.mcpFields["state"] == .string("failed"))
    let file = f.folder.appendingPathComponent("code/a.txt")
    let changed = try await f.tools { _, _ in try Data("user change".utf8).write(to: file); return true }.execute(.init(id: "stale", name: "project_write_file", arguments: args), context: f.context)
    #expect(changed.mcpFields["state"] == .string("failed"))
    #expect(try String(contentsOf: file, encoding: .utf8) == "user change")
    await f.service.suspend()
}

@Test func nativeProcessResultIsDurableReplayDoesNotExecuteAndLogsAreArtifacts() async throws {
    let f = try await NativeWorkspaceFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let tools = f.tools()
    let call = ChatToolCall(id: "run", name: "process_run", arguments: .object(["executable": .string("/bin/sh"), "arguments": .array([.string("-c"), .string("printf once >> count; printf verified; printf errors >&2")])]))
    let started = try await tools.execute(call, context: f.context)
    let id = try #require(started.mcpFields["process_id"]?.mcpString)
    var result = ChatJSON.null
    let end = ContinuousClock.now.advanced(by: .seconds(6))
    while ContinuousClock.now < end {
        result = try await tools.execute(.init(id: "poll", name: "process_status", arguments: .object(["process_id": .string(id)])), context: f.context)
        if result.mcpFields["state"] == .string("succeeded") { break }
        try await _Concurrency.Task.sleep(for: .milliseconds(20))
    }
    #expect(result.mcpFields["stdout"] == .string("verified")); #expect(result.mcpFields["stderr"] == .string("errors"))
    let replay = try await tools.execute(call, context: f.context)
    #expect(replay.mcpFields["state"] == .string("succeeded"))
    #expect(try String(contentsOf: f.folder.appendingPathComponent("code/count"), encoding: .utf8) == "once")
    let projection = try await f.repository.projection(identity: f.identity)
    #expect(projection.invocations.count == 1 && projection.invocations.first?.state == .succeeded)
    #expect(projection.artifacts.count == 1)
    let project = try #require(try await f.repository.records(BlotV3.Project.self, workspaceID: f.identity.workspaceID).first)
    #expect(project.repositoryPath == "device:" + f.identity.deviceID.uuidString)
    await f.service.suspend()
}

@Test func nativeTaskProjectIsInheritedAndPrivateBindingCannotBeReplicatedAsAuthority() async throws {
    let f = try await NativeWorkspaceFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let tasks = WorkspaceTaskService(repository: f.repository, identity: f.identity)
    let parent = try await tasks.create(commandID: UUID(), conversationID: f.conversation, agentID: f.agent, goal: "Parent", executorDeviceID: f.identity.deviceID, projectID: f.project)
    let child = try await tasks.create(commandID: UUID(), conversationID: f.conversation, agentID: f.agent, goal: "Child", executorDeviceID: f.identity.deviceID, parentTaskID: parent)
    #expect(try await f.repository.record(BlotV3.Task.self, id: child, workspaceID: f.identity.workspaceID)?.projectId == f.project)
    let other = try await workspaceTestRepository(url: f.folder.appendingPathComponent("other.sqlite"))
    let otherID = try await other.joinWorkspace(ownerID: f.identity.ownerID, workspaceID: f.identity.workspaceID)
    try await other.installReplicaSnapshot(f.repository.replicaSnapshot(identity: f.identity), identity: otherID)
    let foreign = WorkspaceNativeService(repository: other, identity: otherID, credentials: NativeTestCredentials(),
        files: WorkspaceFileService(repository: other, identity: otherID, directory: f.folder.appendingPathComponent("other-files")), makeExecutor: { NativeExecutor() })
    let provider = WorkspaceNativeTools(service: foreign, repository: other, identity: otherID, confirm: { _, _ in true })
    #expect(try await provider.availableDefinitions(context: f.context).isEmpty)
    await f.service.suspend(); await foreign.suspend()
}

@Test func nativeRevocationWhileConfirmingStopsTheActionAndRemovesConfiguration() async throws {
    let f = try await NativeWorkspaceFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let service = f.service, project = f.project
    let tools = f.tools { _, _ in try await service.disconnect(project); return true }
    let result = try await tools.execute(.init(id: "revoked", name: "process_run", arguments: .object(["executable": .string("/bin/sh"), "arguments": .array([.string("-c"), .string("touch forbidden")])])), context: f.context)
    #expect(result.mcpFields["state"] == .string("failed"))
    #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent("code/forbidden").path))
    #expect(try await service.projects().isEmpty)
    await service.suspend()
}

@Test func nativeProjectDelegationBindsProjectAndAcceptsLegacyTasksWithoutProject() async throws {
    let f = try await NativeWorkspaceFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let phone = try await workspaceTestRepository(url: f.folder.appendingPathComponent("phone.sqlite"))
    let phoneID = try await phone.joinWorkspace(ownerID: f.identity.ownerID, workspaceID: f.identity.workspaceID)
    let macTrust = try await WorkspaceDeviceAuthority.open(identity: f.identity, credentials: f.credentials)
    let phoneTrust = try await WorkspaceDeviceAuthority.open(identity: phoneID, credentials: NativeTestCredentials())
    let invitation = try await macTrust.invite(name: "Mac")
    let claim = try await phoneTrust.claim(invitation, name: "Phone")
    let approval = try await macTrust.approve(claim.token, confirmedCode: claim.code)
    try await phoneTrust.finish(approval)
    try await phone.installReplicaSnapshot(f.repository.replicaSnapshot(identity: f.identity), identity: phoneID)
    let sender = WorkspaceTaskDelegation(repository: phone, identity: phoneID, authority: phoneTrust)
    let id = try await sender.create(commandID: UUID(), conversationID: f.conversation, agentID: f.agent, executorID: f.identity.deviceID, goal: "Native project task", projectID: f.project)
    let legacy = try await sender.create(commandID: UUID(), conversationID: f.conversation, agentID: f.agent, executorID: f.identity.deviceID, goal: "Legacy chat task")
    try await f.repository.installReplicaSnapshot(phone.replicaSnapshot(identity: phoneID), identity: f.identity)
    let receiver = WorkspaceTaskDelegation(repository: f.repository, identity: f.identity, authority: macTrust)
    let task = try #require(try await f.repository.record(BlotV3.Task.self, id: id, workspaceID: f.identity.workspaceID))
    try await receiver.authorize(task)
    try await receiver.authorize(try #require(try await f.repository.record(BlotV3.Task.self, id: legacy, workspaceID: f.identity.workspaceID)))
    var changed = try JSONSerialization.jsonObject(with: WorkspaceCoding.encode(task)) as! [String: Any]
    changed["projectId"] = UUID().uuidString
    let forged = try WorkspaceCoding.decode(BlotV3.Task.self, from: JSONSerialization.data(withJSONObject: changed))
    await #expect(throws: WorkspaceStorageError.permissionDenied) { try await receiver.authorize(forged) }
    await f.service.suspend()
}

@Test func nativePauseTerminatesTheBoundProcessAndFinishesItsInvocation() async throws {
    let f = try await NativeWorkspaceFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let taskID = try await WorkspaceTaskService(repository: f.repository, identity: f.identity).create(commandID: UUID(), conversationID: f.conversation,
        agentID: f.agent, goal: "Long command", executorDeviceID: f.identity.deviceID, projectID: f.project)
    let lifecycle = WorkspaceTaskLifecycle(repository: f.repository, identity: f.identity)
    #expect(try await lifecycle.claim(taskID))
    let sourceID = WorkspaceTaskLifecycle.sourceID(taskID: taskID, workspaceID: f.identity.workspaceID)
    let context = WorkspaceToolContext(sourceMessageID: sourceID, taskID: taskID, allowedToolIDs: Set(WorkspaceNativeCatalog.toolIDs), agentID: f.agent)
    _ = try await f.tools().execute(.init(id: "long", name: "process_run", arguments: .object(["executable": .string("/bin/sleep"), "arguments": .array([.string("30")])])), context: context)
    try await lifecycle.pause(commandID: UUID(), taskID: taskID)
    let end = ContinuousClock.now.advanced(by: .seconds(4))
    while try await f.repository.projection(identity: f.identity).invocations.first?.state == .running, ContinuousClock.now < end {
        try await _Concurrency.Task.sleep(for: .milliseconds(20))
    }
    let projection = try await f.repository.projection(identity: f.identity)
    #expect(projection.invocations.first?.state == .failed)
    #expect(projection.tasks.first(where: { $0.metadata.id == taskID })?.state == .paused)
    await f.service.suspend()
}
#endif
