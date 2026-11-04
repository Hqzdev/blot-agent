import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor BackupTestTransport: WorkspaceCloudBackupTransport {
    private var pending: [UUID: WorkspaceCloudBackupManifest] = [:]
    private var parts: [UUID: [Int: Data]] = [:]
    private var committed: [UUID: WorkspaceCloudBackupManifest] = [:]
    private var failCommit = false
    private(set) var begins = 0
    func failNextCommit() { failCommit = true }
    func manifests() -> [WorkspaceCloudBackupManifest] { Array(committed.values) }
    func begin(_ manifest: WorkspaceCloudBackupManifest) {
        begins += 1; pending[manifest.snapshotID] = manifest
    }
    func upload(snapshotID: UUID, part: Int, data: Data) { parts[snapshotID, default: [:]][part] = data }
    func commit(snapshotID: UUID) throws {
        guard let manifest = pending[snapshotID], parts[snapshotID]?.count == manifest.chunkCount else { throw WorkspaceSyncError.invalidSnapshot }
        committed = committed.filter { $0.value.deviceID != manifest.deviceID }
        committed[snapshotID] = manifest
        if failCommit { failCommit = false; throw URLError(.networkConnectionLost) }
    }
    func download(snapshotID: UUID, part: Int) throws -> Data {
        guard let bytes = parts[snapshotID]?[part] else { throw WorkspaceSyncError.invalidSnapshot }
        return bytes
    }
}

@Test func cloudBackupRestoresChatsAndProjectsAndMergesOfflineEdits() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let first = try await workspaceTestRepository(url: directory.appendingPathComponent("first.sqlite"))
    let second = try await workspaceTestRepository(url: directory.appendingPathComponent("second.sqlite"))
    let a = try await first.localIdentity()
    let b = try await second.joinWorkspace(ownerID: a.ownerID, workspaceID: a.workspaceID)
    let transport = BackupTestTransport()
    let backupA = WorkspaceCloudBackup(repository: first, identity: a, transport: transport)
    let backupB = WorkspaceCloudBackup(repository: second, identity: b, transport: transport)
    let chat = WorkspaceChatService(repository: first, identity: a)
    let projectID = UUID()
    let metadata = try BlotV3.RecordMetadata(id: projectID, ownerId: a.ownerID, workspaceId: a.workspaceID,
        version: 1, createdAt: Date(), updatedAt: Date())
    let project = try BlotV3.Project(metadata: metadata, name: "Saved project", repositoryPath: "/projects/blot")
    try await first.commit(commandID: UUID(), command: Data("create project".utf8), mutations: [WorkspaceRecordMutation(project, expectedVersion: 0)])
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Saved chat", agentID: nil)
    _ = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Saved in PostgreSQL")
    // Exercise chunking with a snapshot larger than one request frame.
    for _ in 0..<6 { _ = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: String(repeating: "a", count: 100_000)) }
    try await backupA.synchronize()
    #expect(await transport.manifests().first!.chunkCount > 1)
    try await backupB.synchronize()
    #expect(try await second.projection(identity: b).messages.count == 7)
    #expect(try await second.record(BlotV3.Project.self, id: projectID, workspaceID: b.workspaceID)?.name == "Saved project")
    _ = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Offline first")
    _ = try await WorkspaceChatService(repository: second, identity: b).sendMessage(commandID: UUID(), conversationID: conversation, content: "Offline second")
    try await backupA.synchronize()
    try await backupB.synchronize()
    try await backupA.synchronize()
    #expect(try await first.projection(identity: a).messages.count == 9)
    #expect(try await second.projection(identity: b).messages.count == 9)
    let uploaded = await transport.begins
    try await backupA.synchronize()
    try await backupA.synchronize()
    #expect(await transport.begins <= uploaded + 1)
    try await first.close(); try await second.close()
}

@Test func cloudBackupRetriesTheSameSnapshotAfterLostCommitResponse() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("retry.sqlite"))
    let identity = try await repository.localIdentity()
    let transport = BackupTestTransport()
    let backup = WorkspaceCloudBackup(repository: repository, identity: identity, transport: transport)
    _ = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Retry", agentID: nil)
    await transport.failNextCommit()
    await #expect(throws: URLError.self) { try await backup.synchronize() }
    let initial = await transport.manifests().first!.snapshotID
    try await backup.synchronize()
    #expect(await transport.manifests().first!.snapshotID == initial)
    #expect(await transport.begins == 2)
    try await repository.close()
}
