import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor DelegationCredentials: WorkspaceCredentialPruning {
    var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
    func removeNames(prefixes: [String]) { values = values.filter { key, _ in !prefixes.contains(where: key.hasPrefix) } }
}
private struct DelegationPair {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let phone: WorkspaceRepository; let mac: WorkspaceRepository
    let phoneID: WorkspaceIdentity; let macID: WorkspaceIdentity
    let phoneCredentials = DelegationCredentials(), macCredentials = DelegationCredentials()
    let phoneTrust: WorkspaceDeviceAuthority; let macTrust: WorkspaceDeviceAuthority
    init() async throws {
        phone = try await workspaceTestRepository(url: directory.appendingPathComponent("phone.sqlite")); phoneID = try await phone.localIdentity()
        mac = try await workspaceTestRepository(url: directory.appendingPathComponent("mac.sqlite")); macID = try await mac.joinWorkspace(ownerID: phoneID.ownerID, workspaceID: phoneID.workspaceID)
        phoneTrust = try await .open(identity: phoneID, credentials: phoneCredentials)
        macTrust = try await .open(identity: macID, credentials: macCredentials)
    }
    func pair() async throws {
        let invite = try await macTrust.invite(name: "Work Mac")
        let claim = try await phoneTrust.claim(invite, name: "My iPhone")
        let inspected = try await macTrust.inspect(claim.token)
        #expect(inspected.code == claim.code)
        let approval = try await macTrust.approve(claim.token, confirmedCode: inspected.code)
        try await phoneTrust.finish(approval)
    }
    var sender: WorkspaceTaskDelegation { .init(repository: phone, identity: phoneID, authority: phoneTrust) }
    var receiver: WorkspaceTaskDelegation { .init(repository: mac, identity: macID, authority: macTrust) }
    func create() async throws -> UUID {
        let agent = try await WorkspaceAgentService(repository: phone, identity: phoneID).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Do the task"))
        let chat = try await WorkspaceChatService(repository: phone, identity: phoneID).createConversation(commandID: UUID(), title: "Remote task", agentID: agent)
        return try await sender.create(commandID: UUID(), conversationID: chat, agentID: agent, executorID: macID.deviceID, goal: "Write a concise result")
    }
    func transfer() async throws { try await mac.installReplicaSnapshot(phone.replicaSnapshot(identity: phoneID), identity: macID) }
}
private actor DelegatedModel: ChatModel {
    let before: (@Sendable () async throws -> Void)?
    private(set) var calls = 0
    init(before: (@Sendable () async throws -> Void)? = nil) { self.before = before }
    func begin() async throws { calls += 1; try await before?() }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task {
                do { try await self.begin(); continuation.yield(.text("Completed on Mac.")); continuation.yield(.finished(.stop)); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
        }
    }
}

@Test func pairingRequiresMatchingCodeAndBoundAccountAndSurvivesReopen() async throws {
    let p = try await DelegationPair(); defer { cleanupWorkspaceTestStorage(p.directory) }
    let invite = try await p.macTrust.invite(name: "Mac")
    let claim = try await p.phoneTrust.claim(invite, name: "Phone")
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await p.macTrust.approve(claim.token, confirmedCode: "wrong") }
    #expect(try await p.macTrust.devices().isEmpty)
    let approval = try await p.macTrust.approve(claim.token, confirmedCode: claim.code)
    try await p.phoneTrust.finish(approval)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { try await p.phoneTrust.finish(approval) }
    let reopened = try await WorkspaceDeviceAuthority.open(identity: p.macID, credentials: p.macCredentials)
    #expect(try await reopened.peer(p.phoneID.deviceID).kind == .phone)
    let foreign = try await WorkspaceDeviceAuthority.open(identity: .init(ownerID: UUID(), workspaceID: p.macID.workspaceID, deviceID: UUID()), credentials: DelegationCredentials())
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await foreign.claim(invite, name: "Other account") }
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await p.phoneTrust.claim(invite, name: "Expired", now: Date().addingTimeInterval(601)) }
}

@Test func signedPhoneTaskExecutesOnlyOnPairedMacAndReplayedSnapshotDoesNotRunAgain() async throws {
    let p = try await DelegationPair(); defer { cleanupWorkspaceTestStorage(p.directory) }
    try await p.pair(); let id = try await p.create(); try await p.transfer()
    let task = try #require(try await p.mac.record(BlotV3.Task.self, id: id, workspaceID: p.macID.workspaceID))
    try await p.receiver.authorize(task)
    let untrusted = try await WorkspaceDeviceAuthority.open(identity: p.macID, credentials: DelegationCredentials())
    await #expect(throws: WorkspaceStorageError.permissionDenied) { try await WorkspaceTaskDelegation(repository: p.mac, identity: p.macID, authority: untrusted).authorize(task) }
    let model = DelegatedModel()
    let execute = WorkspaceTaskExecution(repository: p.mac, identity: p.macID, pool: .init(), tools: try .init(providers: []), maximumOutputTokens: 64, authorize: { try await p.receiver.authorize($0) })
    try await execute.run(taskID: id, model: model)
    #expect(try await p.mac.record(BlotV3.Task.self, id: id, workspaceID: p.macID.workspaceID)?.state == .completed)
    try await p.transfer(); try await execute.run(taskID: id, model: model)
    #expect(await model.calls == 1)
    let result = try await p.mac.replicaSnapshot(identity: p.macID)
    try await p.phone.installReplicaSnapshot(result, identity: p.phoneID)
    #expect(try await p.phone.projection(identity: p.phoneID).messages.contains { $0.content == "Completed on Mac." })
}

@Test func delegationRejectsTamperingAndRevocationDuringGeneration() async throws {
    let p = try await DelegationPair(); defer { cleanupWorkspaceTestStorage(p.directory) }
    try await p.pair(); let id = try await p.create(); try await p.transfer()
    let original = try #require(try await p.mac.record(BlotV3.Task.self, id: id, workspaceID: p.macID.workspaceID))
    let tampered = try BlotV3.Task(metadata: original.metadata, execution: original.execution, conversationId: original.conversationId,
        goal: "Different task", state: original.state, plan: original.plan, configurationId: original.configurationId,
        budgetTokenLimit: original.budgetTokenLimit, executionMode: original.executionMode, authorizationJSON: original.authorizationJSON)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { try await p.receiver.authorize(tampered) }
    let changedExecution = try BlotV3.ExecutionContext(executorDeviceId: p.macID.deviceID, originDeviceId: p.phoneID.deviceID, taskId: UUID(), revision: 1)
    let mismatched = try BlotV3.Task(metadata: original.metadata, execution: changedExecution, conversationId: original.conversationId,
        goal: original.goal, state: original.state, plan: original.plan, configurationId: original.configurationId,
        budgetTokenLimit: original.budgetTokenLimit, executionMode: original.executionMode, authorizationJSON: original.authorizationJSON)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { try await p.receiver.authorize(mismatched) }
    let model = DelegatedModel { try await p.macTrust.revoke(p.phoneID.deviceID) }
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        try await WorkspaceTaskExecution(repository: p.mac, identity: p.macID, pool: .init(), tools: .init(providers: []), maximumOutputTokens: 64,
            authorize: { try await p.receiver.authorize($0) }).run(taskID: id, model: model)
    }
    #expect(try await p.mac.record(BlotV3.Task.self, id: id, workspaceID: p.macID.workspaceID)?.state == .failed)
    #expect(try await p.mac.projection(identity: p.macID).messages.allSatisfy { $0.delivery != .completed || $0.role == .user })
}

@Test func accountCleanupResumesAfterFailureAndPreservesOtherAccounts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let identity = WorkspaceIdentity(ownerID: UUID(), workspaceID: UUID(), deviceID: UUID()), other = UUID()
    let target = directory.appendingPathComponent(identity.ownerID.uuidString).appendingPathComponent(identity.workspaceID.uuidString)
    let unrelated = directory.appendingPathComponent(other.uuidString)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    try Data("private".utf8).write(to: target.appendingPathComponent("workspace.sqlite"))
    try Data("other owner".utf8).write(to: unrelated.appendingPathComponent("keep.txt"))
    let credentials = DelegationCredentials()
    await credentials.write(Data("secret".utf8), name: "device-keys:" + identity.workspaceID.uuidString + ":old-device")
    await credentials.write(Data("other".utf8), name: "profile:" + other.uuidString)
    let erasure = WorkspaceAccountErasure(root: directory, credentials: credentials)
    try erasure.mark(identity)
    await #expect(throws: WorkspaceCredentialError.invalidValue) { try await erasure.resume { _ in throw WorkspaceCredentialError.invalidValue } }
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending-account-deletion.json").path))
    try await erasure.resume()
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending-account-deletion.json").path))
    #expect(await credentials.read("device-keys:" + identity.workspaceID.uuidString + ":old-device") == nil)
    #expect(await credentials.read("profile:" + other.uuidString) != nil)
    #expect(try String(contentsOf: unrelated.appendingPathComponent("keep.txt"), encoding: .utf8) == "other owner")
}

@Test func accountCleanupCannotUnlinkAnActiveWorkspaceOrFollowAnAccountSymlink() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(root) }
    let identity = WorkspaceIdentity(ownerID: UUID(), workspaceID: UUID(), deviceID: UUID())
    let directory = root.appendingPathComponent(identity.ownerID.uuidString).appendingPathComponent(identity.workspaceID.uuidString)
    let erasure = WorkspaceAccountErasure(root: root, credentials: DelegationCredentials())
    do {
        let lock = try WorkspaceProcessLock(directory: directory)
        try erasure.mark(identity)
        await #expect(throws: WorkspaceStorageError.permissionDenied) { try await erasure.resume() }
        withExtendedLifetime(lock) {}
    }
    try await erasure.resume()
    let outside = root.appendingPathComponent("other-data")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(identity.ownerID.uuidString), withDestinationURL: outside)
    #expect(throws: WorkspaceFileError.unsafePath) { try erasure.mark(identity) }
}

@Test func groupPlanValidatesDependenciesAndLegacyIndependentSteps() throws {
    let a = UUID(), b = UUID()
    let valid = "{\"summary\":\"Plan\",\"assignments\":[{\"agentID\":\"\(a)\",\"task\":\"Research\"},{\"agentID\":\"\(b)\",\"task\":\"Use results\",\"dependsOn\":[\"\(a)\"]}]}"
    let plan = try WorkspaceGroupPlan.decode(valid, memberIDs: [a,b])
    #expect(plan.assignments[0].dependsOn.isEmpty && plan.assignments[1].dependsOn == [a])
    let cycle = valid.replacingOccurrences(of: "\"task\":\"Research\"", with: "\"task\":\"Research\",\"dependsOn\":[\"\(b)\"]")
    #expect(throws: ChatModelError.invalidStream) { _ = try WorkspaceGroupPlan.decode(cycle, memberIDs: [a,b]) }
}

@Test func groupHandoffsReuseCompletedWritesButDoNotRetryUnknownOutcomes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(root) }
    let repository = try await workspaceTestRepository(url: root.appendingPathComponent("group.sqlite")), identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Writer", instructions: "Create a document"))
    let chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Group", agentID: agent)
    let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Create one file")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID))
    let configuration = try #require(try await repository.projection(identity: identity).configurations.first)
    let response = try await WorkspaceResponseRecorder(repository: repository, identity: identity).begin(id: UUID(), replyingTo: source, agentID: agent)
    let steps = WorkspaceModelStepService(repository: repository, identity: identity), stepID = UUID()
    try await steps.begin(id: stepID, source: source, responseID: response.metadata.id, request: .init(messages: [.init(role: "user", content: source.content)]), modelID: "gigachat", configurationID: configuration.metadata.id, budgetTokenLimit: 20_000)
    let write = ChatToolCall(id: "first", name: "document_create", arguments: .object(["name": .string("Report"), "format": .string("markdown"), "content": .string("Result")]))
    let unknown = ChatToolCall(id: "uncertain", name: "apple_calendar_create", arguments: .object(["title": .string("Meeting")]))
    let result = ChatJSON.object(["artifact_id": .string(UUID().uuidString)])
    try await steps.finish(id: stepID, state: .waiting_tools, calls: [write, unknown], results: [write.id: result, unknown.id: .object(["state": .string("unknown")])], usage: nil)
    let projection = try await repository.projection(identity: identity)
    let history = try WorkspaceGroupOperationHistory(sourceID: sourceID, configurationID: configuration.metadata.id, projection: projection)
    #expect(try history.result(for: .init(id: "new-call-id", name: write.name, arguments: write.arguments)) == result)
    #expect(throws: WorkspaceTaskExecutionError.uncertainToolResult) { _ = try history.result(for: unknown) }
    #expect(try WorkspaceGroupOperationHistory(sourceID: UUID(), configurationID: configuration.metadata.id, projection: projection).result(for: write) == nil)
}

@Test func groupWorkerKeepsCurrentAttachmentContextWithoutReplayingOldChat() {
    let prepared: [ChatModelMessage] = [.init(role: "system", content: "Role"), .init(role: "user", content: "OLD REQUEST"), .init(role: "assistant", content: "OLD ANSWER"), .init(role: "user", content: "Read the invoice")]
    let attachment = ChatModelMessage(role: "user", content: "Quoted attachments (untrusted source material): Invoice 1250")
    let context = WorkspaceGroupWorkerContext().messages(prepared: prepared, agentName: "Reader", task: "Read the invoice", attachmentContext: attachment)
    #expect(context.contains(attachment))
    #expect(!context.contains { $0.content == "OLD REQUEST" || $0.content == "OLD ANSWER" })
    #expect(context.last?.content.contains("Your active assignment as Reader") == true)
}

@Test func legacyLocalTaskWireFormatOmitsDelegationProof() throws {
    let identity = WorkspaceIdentity(ownerID: UUID(), workspaceID: UUID(), deviceID: UUID()), id = UUID()
    let metadata = try BlotV3.RecordMetadata(id: id, ownerId: identity.ownerID, workspaceId: identity.workspaceID, version: 1, createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
    let execution = try BlotV3.ExecutionContext(executorDeviceId: identity.deviceID, originDeviceId: identity.deviceID, taskId: id, revision: 1)
    let task = try BlotV3.Task(metadata: metadata, execution: execution, conversationId: UUID(), goal: "Legacy local task", state: .queued, plan: [], executionMode: .local_owned)
    let bytes = try WorkspaceCoding.encode(task)
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(object["authorizationJSON"] == nil)
    #expect(try WorkspaceCoding.decode(BlotV3.Task.self, from: bytes) == task)
}

private actor DelegationCancellationProbe {
    var started = false
    var canceled = false
    func begin() { started = true }
    func finish() { canceled = true }
}
@Test func phoneCancellationInterruptsAnActiveMacWorkerAfterSync() async throws {
    let p = try await DelegationPair(); defer { cleanupWorkspaceTestStorage(p.directory) }
    try await p.pair(); let taskID = try await p.create(); try await p.transfer()
    let probe = DelegationCancellationProbe()
    let queue = WorkspaceTaskQueue(repository: p.mac, identity: p.macID, authorize: { try await p.receiver.authorize($0) }, execute: { id in
        let lifecycle = WorkspaceTaskLifecycle(repository: p.mac, identity: p.macID, authorize: { try await p.receiver.authorize($0) })
        guard try await lifecycle.claim(id) else { return }
        await probe.begin()
        do { try await _Concurrency.Task.sleep(for: .seconds(30)) } catch { await probe.finish() }
    })
    await queue.start()
    let start = ContinuousClock.now.advanced(by: .seconds(3))
    while await !probe.started, ContinuousClock.now < start { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
    #expect(await probe.started)
    try await p.phone.installReplicaSnapshot(p.mac.replicaSnapshot(identity: p.macID), identity: p.phoneID)
    try await WorkspaceTaskService(repository: p.phone, identity: p.phoneID).cancel(commandID: UUID(), taskID: taskID)
    try await p.transfer()
    let end = ContinuousClock.now.advanced(by: .seconds(3))
    while await !probe.canceled, ContinuousClock.now < end { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
    #expect(await probe.canceled)
    #expect(try await p.mac.record(BlotV3.Task.self, id: taskID, workspaceID: p.macID.workspaceID)?.state == .canceled)
    await queue.stop()
}

@Test func synchronizedTaskCannotImpersonateLocallyCreatedMacWork() async throws {
    let p = try await DelegationPair(); defer { cleanupWorkspaceTestStorage(p.directory) }
    let agent = try await WorkspaceAgentService(repository: p.phone, identity: p.phoneID).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Work"))
    let chat = try await WorkspaceChatService(repository: p.phone, identity: p.phoneID).createConversation(commandID: UUID(), title: "Forged", agentID: agent)
    let configuration = try #require(try await p.phone.projection(identity: p.phoneID).configurations.first)
    let id = UUID()
    let metadata = try BlotV3.RecordMetadata(id: id, ownerId: p.phoneID.ownerID, workspaceId: p.phoneID.workspaceID, version: 1, createdAt: Date(), updatedAt: Date())
    let execution = try BlotV3.ExecutionContext(executorDeviceId: p.macID.deviceID, originDeviceId: p.macID.deviceID, taskId: id, revision: 1)
    let forged = try BlotV3.Task(metadata: metadata, execution: execution, conversationId: chat, goal: "Unsigned work pretending to originate on Mac", state: .queued, plan: [], configurationId: configuration.metadata.id, budgetTokenLimit: 20_000, executionMode: .local_owned)
    try await p.phone.commit(commandID: UUID(), command: Data("forged cloud task".utf8), mutations: [WorkspaceRecordMutation(forged, expectedVersion: 0)])
    try await p.transfer()
    #expect(try await !p.mac.executionAdmitted(forged, identity: p.macID))
    let model = DelegatedModel()
    let executionService = WorkspaceTaskExecution(repository: p.mac, identity: p.macID, pool: .init(), tools: try .init(providers: []), maximumOutputTokens: 64)
    try await executionService.run(taskID: id, model: model)
    #expect(await model.calls == 0)
}

@Test func localTerminalReceiptPreventsReplayEvenWhenSyncedHistoryIsRemoved() async throws {
    let p = try await DelegationPair(); defer { cleanupWorkspaceTestStorage(p.directory) }
    try await p.pair(); let id = try await p.create(); try await p.transfer()
    let model = DelegatedModel()
    let executor = WorkspaceTaskExecution(repository: p.mac, identity: p.macID, pool: .init(), tools: try .init(providers: []), maximumOutputTokens: 64, authorize: { try await p.receiver.authorize($0) })
    try await executor.run(taskID: id, model: model)
    let projection = try await p.mac.projection(identity: p.macID), old = try #require(projection.tasks.first)
    let metadata = try BlotV3.RecordMetadata(id: old.metadata.id, ownerId: old.metadata.ownerId, workspaceId: old.metadata.workspaceId, version: old.metadata.version + 1, createdAt: old.metadata.createdAt, updatedAt: Date())
    let replay = try BlotV3.Task(metadata: metadata, execution: old.execution, conversationId: old.conversationId, goal: old.goal, state: .queued, plan: old.plan, configurationId: old.configurationId, budgetTokenLimit: old.budgetTokenLimit, executionMode: old.executionMode, authorizationJSON: old.authorizationJSON)
    var mutations = [try WorkspaceRecordMutation(replay, expectedVersion: old.metadata.version)]
    mutations += try projection.modelSteps.map { try WorkspaceRecordMutation(deleting: $0) }
    mutations += try projection.messages.map { try WorkspaceRecordMutation(deleting: $0) }
    try await p.mac.commit(commandID: UUID(), command: Data("restore queued task without history".utf8), mutations: mutations)
    #expect(try await !p.mac.executionAdmitted(replay, identity: p.macID))
    try await executor.run(taskID: id, model: model)
    #expect(await model.calls == 1)
}

@Test func syncedEditsCannotReplaceTheGoalOfLocallyAuthorizedWork() async throws {
    let p = try await DelegationPair(); defer { cleanupWorkspaceTestStorage(p.directory) }
    let agent = try await WorkspaceAgentService(repository: p.mac, identity: p.macID).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Work"))
    let chat = try await WorkspaceChatService(repository: p.mac, identity: p.macID).createConversation(commandID: UUID(), title: "Local", agentID: agent)
    let id = try await WorkspaceTaskService(repository: p.mac, identity: p.macID).create(commandID: UUID(), conversationID: chat, agentID: agent, goal: "Original goal", executorDeviceID: p.macID.deviceID)
    let old = try #require(try await p.mac.record(BlotV3.Task.self, id: id, workspaceID: p.macID.workspaceID))
    #expect(try await p.mac.executionAdmitted(old, identity: p.macID))
    try await p.phone.installReplicaSnapshot(p.mac.replicaSnapshot(identity: p.macID), identity: p.phoneID)
    let metadata = try BlotV3.RecordMetadata(id: id, ownerId: old.metadata.ownerId, workspaceId: old.metadata.workspaceId, version: old.metadata.version + 1, createdAt: old.metadata.createdAt, updatedAt: Date())
    let edited = try BlotV3.Task(metadata: metadata, execution: old.execution, conversationId: chat, goal: "Changed on another device", state: .queued, plan: [], configurationId: old.configurationId, budgetTokenLimit: old.budgetTokenLimit, executionMode: .local_owned)
    try await p.phone.commit(commandID: UUID(), command: Data("replace local goal".utf8), mutations: [WorkspaceRecordMutation(edited, expectedVersion: old.metadata.version)])
    try await p.transfer()
    let received = try #require(try await p.mac.record(BlotV3.Task.self, id: id, workspaceID: p.macID.workspaceID))
    #expect(received.goal == edited.goal)
    #expect(try await !p.mac.executionAdmitted(received, identity: p.macID))
    #expect(try await !WorkspaceTaskLifecycle(repository: p.mac, identity: p.macID).claim(id))
}
