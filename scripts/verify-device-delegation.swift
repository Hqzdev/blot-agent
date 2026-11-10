import BlotDomain
import BlotWorkspace
import Foundation

private actor DeviceCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}
private actor DeviceBackupTransport: WorkspaceCloudBackupTransport {
    private var pending: [UUID: WorkspaceCloudBackupManifest] = [:]
    private var committed: [UUID: WorkspaceCloudBackupManifest] = [:]
    private var parts: [UUID: [Int: Data]] = [:]
    func manifests() -> [WorkspaceCloudBackupManifest] { Array(committed.values) }
    func begin(_ manifest: WorkspaceCloudBackupManifest) { pending[manifest.snapshotID] = manifest }
    func upload(snapshotID: UUID, part: Int, data: Data) { parts[snapshotID, default: [:]][part] = data }
    func commit(snapshotID: UUID) throws {
        guard let manifest = pending[snapshotID], parts[snapshotID]?.count == manifest.chunkCount else { throw WorkspaceSyncError.invalidSnapshot }
        committed = committed.filter { $0.value.deviceID != manifest.deviceID }; committed[snapshotID] = manifest
    }
    func download(snapshotID: UUID, part: Int) throws -> Data {
        guard let data = parts[snapshotID]?[part] else { throw WorkspaceSyncError.invalidSnapshot }; return data
    }
}
private actor MacTaskModel: ChatModel {
    private(set) var calls = 0
    func events() -> [ChatModelEvent] { calls += 1; return [.text("Executed on the selected Mac."), .finished(.stop)] }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task { for event in await self.events() { continuation.yield(event) }; continuation.finish() }
        }
    }
}
@main struct VerifyDeviceDelegation {
    static func require(_ value: Bool, _ message: String = "Unexpected delegation state") { precondition(value, message) }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !condition(), ContinuousClock.now < end { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        require(try await condition(), "Timed out waiting for the delegated task")
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = try WorkspaceRepository(url: root.appendingPathComponent("phone.sqlite")), phoneID = try await phone.localIdentity()
        let mac = try WorkspaceRepository(url: root.appendingPathComponent("mac.sqlite")), macID = try await mac.joinWorkspace(ownerID: phoneID.ownerID, workspaceID: phoneID.workspaceID)
        let phoneCredentials = DeviceCredentials(), macCredentials = DeviceCredentials()
        let phoneTrust = try await WorkspaceDeviceAuthority.open(identity: phoneID, credentials: phoneCredentials)
        let macTrust = try await WorkspaceDeviceAuthority.open(identity: macID, credentials: macCredentials)
        let model = MacTaskModel()
        let phoneService = try LocalWorkspaceService(databaseURL: root.appendingPathComponent("phone.sqlite"), repository: phone, identity: phoneID, maximumOutputTokens: 64, deviceAuthority: phoneTrust, makeModel: { _ in model })
        let macService = try LocalWorkspaceService(databaseURL: root.appendingPathComponent("mac.sqlite"), repository: mac, identity: macID, maximumOutputTokens: 64, deviceAuthority: macTrust, makeModel: { _ in model })
        _ = try await phoneService.load(); _ = try await macService.load()
        let invite = try await macService.createDeviceInvite()
        let claim = try await phoneService.claimDevice(invite)
        let candidate = try await macService.inspectDeviceClaim(claim.token)
        require(candidate.code == claim.code, "Pairing codes differ")
        let approval = try await macService.approveDevice(claim.token, code: candidate.code)
        try await phoneService.finishDevicePairing(approval)
        require(try await phoneService.currentSnapshot().pairedDevices?.first?.id == macID.deviceID)
        print("PASS: real service pairing exchange and local trust snapshots")

        let agent = try await WorkspaceAgentService(repository: phone, identity: phoneID).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Do one task", modelID: "gigachat"))
        let chat = try await WorkspaceChatService(repository: phone, identity: phoneID).createConversation(commandID: UUID(), title: "Remote", agentID: agent)
        let task = try await phoneService.delegateTask(conversationID: chat, agentID: agent, deviceID: macID.deviceID, goal: "Write one short result")
        require(await model.calls == 0, "Phone executed work assigned to Mac")
        let transport = DeviceBackupTransport()
        let phoneBackup = WorkspaceCloudBackup(repository: phone, identity: phoneID, transport: transport)
        let macBackup = WorkspaceCloudBackup(repository: mac, identity: macID, transport: transport)
        try await phoneBackup.synchronize(); try await macBackup.synchronize()
        try await wait { try await macService.currentSnapshot().tasks?.first(where: { $0.metadata.id == task })?.state == .completed }
        try await macBackup.synchronize(); try await phoneBackup.synchronize()
        let received = try await phoneService.currentSnapshot()
        require(received.tasks?.first(where: { $0.metadata.id == task })?.state == .completed)
        require(received.messages.contains { $0.content == "Executed on the selected Mac." })
        require(await model.calls == 1)
        print("PASS: signed task syncs to Mac, executes once and returns its result to phone")

        await macService.suspendAccountOperations()
        try await macService.resumeAccountOperations()
        let resumed = try await phoneService.delegateTask(conversationID: chat, agentID: agent, deviceID: macID.deviceID, goal: "Run after a failed deletion request")
        try await phoneBackup.synchronize(); try await macBackup.synchronize()
        try await wait { try await macService.currentSnapshot().tasks?.first(where: { $0.metadata.id == resumed })?.state == .completed }
        require(await model.calls == 2)
        print("PASS: account deletion quiesces execution and can resume it after a rejected request")
        try await macService.revokePairedDevice(phoneID.deviceID)
        let blocked = try await phoneService.delegateTask(conversationID: chat, agentID: agent, deviceID: macID.deviceID, goal: "This must not execute")
        try await phoneBackup.synchronize(); try await macBackup.synchronize()
        let record = try await mac.record(BlotV3.Task.self, id: blocked, workspaceID: macID.workspaceID)!
        do {
            try await WorkspaceTaskDelegation(repository: mac, identity: macID, authority: macTrust).authorize(record)
            preconditionFailure("Revoked device was authorized")
        } catch WorkspaceStorageError.permissionDenied {}
        try await _Concurrency.Task.sleep(for: .milliseconds(100))
        require(await model.calls == 2)
        require(try await macService.currentSnapshot().tasks?.first(where: { $0.metadata.id == blocked })?.state == .queued)
        await macService.stopAll(); await phoneService.stopAll()
        let reopened = try await WorkspaceDeviceAuthority.open(identity: macID, credentials: macCredentials)
        require(try await reopened.devices().first?.revoked == true)
        print("PASS: recipient revocation blocks queued remote work and persists across restart")
    }
}
