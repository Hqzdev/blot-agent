import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor PeerCredentials: WorkspaceCredentialStore {
    var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}
private struct PeerTrust: WorkspaceDeviceTrust {
    let signingKeys: [UUID: Data]
    func signingKey(for deviceID: UUID, sequence: Int64) throws -> Data {
        guard let value = signingKeys[deviceID] else { throw WorkspaceSyncError.invalidSignature }
        return value
    }
}

@Test func directPeerSnapshotsConvergeWithoutRelayAndDoNotTransferExecution() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let first = try await workspaceTestRepository(url: directory.appendingPathComponent("first.sqlite"))
    let second = try await workspaceTestRepository(url: directory.appendingPathComponent("second.sqlite"))
    let a = try await first.localIdentity()
    let b = try await second.joinWorkspace(ownerID: a.ownerID, workspaceID: a.workspaceID)
    let keysA = try await WorkspaceDeviceKeys.open(identity: a, credentials: PeerCredentials())
    let keysB = try await WorkspaceDeviceKeys.open(identity: b, credentials: PeerCredentials())
    try await keysA.initializeWorkspace()
    let publicA = try await keysA.publicKeys(), publicB = try await keysB.publicKeys()
    let grant = try await keysA.wrapKeys(for: b.deviceID, encryptionKey: publicB.encryptionKey)
    _ = try await keysB.acceptWrappedKeys(grant, signerID: a.deviceID, epoch: 1)
    let trust = PeerTrust(signingKeys: [a.deviceID: publicA.signingKey, b.deviceID: publicB.signingKey])
    let peerA = WorkspacePeerSync(repository: first, identity: a, keys: keysA, trust: trust)
    let peerB = WorkspacePeerSync(repository: second, identity: b, keys: keysB, trust: trust)
    let challengeA = try await peerA.challenge(peerID: b.deviceID)
    let challengeB = try await peerB.challenge(peerID: a.deviceID)
    try await peerA.accept(peerB.hello(recipientID: a.deviceID, challenge: challengeA))
    try await peerB.accept(peerA.hello(recipientID: b.deviceID, challenge: challengeB))
    let chatA = WorkspaceChatService(repository: first, identity: a)
    let conversation = try await chatA.createConversation(commandID: UUID(), title: "Nearby", agentID: nil)
    _ = try await chatA.sendMessage(commandID: UUID(), conversationID: conversation, content: "First offline message")
    let original = try await peerA.snapshot(for: b.deviceID)
    let receipt = try await peerB.receive(original, from: a.deviceID)
    try await peerA.acknowledge(receipt)
    _ = try await WorkspaceChatService(repository: second, identity: b).sendMessage(commandID: UUID(), conversationID: conversation, content: "Second offline message")
    _ = try await chatA.sendMessage(commandID: UUID(), conversationID: conversation, content: "Another first message")
    let packetA = try await peerA.snapshot(for: b.deviceID)
    let packetB = try await peerB.snapshot(for: a.deviceID)
    _ = try await peerA.receive(packetB, from: b.deviceID)
    _ = try await peerB.receive(packetA, from: a.deviceID)
    _ = try await peerB.receive(packetA, from: a.deviceID)
    let messagesA = try await first.projection(identity: a).messages
    let messagesB = try await second.projection(identity: b).messages
    #expect(Set(messagesA.map(\.metadata.id)) == Set(messagesB.map(\.metadata.id)))
    #expect(messagesA.count == 3)
    #expect(try await first.relayCursor() == 0)
    #expect(try await second.relayCursor() == 0)
    #expect(try await first.pendingSyncChanges().count > 0)
    await #expect(throws: WorkspaceSyncError.identityMismatch) {
        try await peerA.accept(peerB.hello(recipientID: a.deviceID, challenge: challengeA))
    }
    await peerA.disconnect(peerID: b.deviceID)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await peerA.snapshot(for: b.deviceID) }
}
