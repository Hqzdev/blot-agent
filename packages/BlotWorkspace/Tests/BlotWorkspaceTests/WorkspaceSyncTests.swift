import BlotDomain
import CryptoKit
import Foundation
import Testing
@testable import BlotWorkspace

private actor CiphertextRelay {
    enum Failure: Error { case lostUploadResponse }
    private var deliveries: [WorkspaceRelayDelivery] = []
    private var failNextUpload = false
    private var acknowledgements: [UUID: Int64] = [:]
    func loseNextUploadResponse() { failNextUpload = true }
    func accepted(_ id: UUID) -> Bool { deliveries.contains { $0.packet.changeID == id } }
    func upload(_ packet: WorkspaceEncryptedPacket) throws -> UUID {
        if let existing = deliveries.first(where: { $0.packet.changeID == packet.changeID }) {
            guard existing.packet == packet else { throw WorkspaceSyncError.replayConflict }
            return packet.changeID
        }
        deliveries.append(.init(sequence: Int64(deliveries.count + 1), packet: packet))
        if failNextUpload { failNextUpload = false; throw Failure.lostUploadResponse }
        return packet.changeID
    }
    func pull(after cursor: Int64, limit: Int) -> WorkspaceRelayBatch {
        let next = Array(deliveries.filter { $0.sequence > cursor }.prefix(limit))
        let end = next.last?.sequence ?? cursor
        return .init(deliveries: next, cursor: end, hasMore: end < deliveries.count)
    }
    func acknowledge(_ device: UUID, cursor: Int64) { acknowledgements[device] = max(acknowledgements[device] ?? 0, cursor) }
    func count() -> Int { deliveries.count }
    func bytes() throws -> Data { try WorkspaceCoding.encode(deliveries) }
}

private struct RelayClient: WorkspaceSyncTransport {
    let relay: CiphertextRelay
    let deviceID: UUID
    func hasAccepted(changeID: UUID) async throws -> Bool { await relay.accepted(changeID) }
    func upload(_ packet: WorkspaceEncryptedPacket) async throws -> UUID { try await relay.upload(packet) }
    func pull(after cursor: Int64, limit: Int) async throws -> WorkspaceRelayBatch { await relay.pull(after: cursor, limit: limit) }
    func acknowledge(upTo cursor: Int64) async throws { await relay.acknowledge(deviceID, cursor: cursor) }
}

private struct TestDeviceTrust: WorkspaceDeviceTrust {
    let keys: [UUID: Data]
    func signingKey(for deviceID: UUID, sequence: Int64) async throws -> Data {
        guard let key = keys[deviceID] else { throw WorkspaceSyncError.invalidSignature }
        return key
    }
}

private struct SyncPair {
    let directory: URL
    let a: WorkspaceRepository
    let b: WorkspaceRepository
    let identityA: WorkspaceIdentity
    let identityB: WorkspaceIdentity
    let cryptoA: WorkspaceSyncCryptography
    let cryptoB: WorkspaceSyncCryptography
    let signerA: Data
    let signerB: Data
    let epochKey: Data
    let relay = CiphertextRelay()
    let trust: TestDeviceTrust
    let engineA: WorkspaceSyncEngine
    let engineB: WorkspaceSyncEngine

    init() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.directory = directory
        a = try await workspaceTestRepository(url: directory.appendingPathComponent("a.sqlite"))
        b = try await workspaceTestRepository(url: directory.appendingPathComponent("b.sqlite"))
        identityA = try await a.localIdentity()
        identityB = try await b.joinWorkspace(ownerID: identityA.ownerID, workspaceID: identityA.workspaceID)
        signerA = P256.Signing.PrivateKey().rawRepresentation
        signerB = P256.Signing.PrivateKey().rawRepresentation
        epochKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        cryptoA = try WorkspaceSyncCryptography(identity: identityA, signingPrivateKey: signerA, epochKeys: [1: epochKey], currentEpoch: 1)
        cryptoB = try WorkspaceSyncCryptography(identity: identityB, signingPrivateKey: signerB, epochKeys: [1: epochKey], currentEpoch: 1)
        trust = TestDeviceTrust(keys: [identityA.deviceID: try P256.Signing.PrivateKey(rawRepresentation: signerA).publicKey.x963Representation,
                                      identityB.deviceID: try P256.Signing.PrivateKey(rawRepresentation: signerB).publicKey.x963Representation])
        engineA = WorkspaceSyncEngine(repository: a, identity: identityA, cryptography: cryptoA,
            transport: RelayClient(relay: relay, deviceID: identityA.deviceID), trust: trust)
        engineB = WorkspaceSyncEngine(repository: b, identity: identityB, cryptography: cryptoB,
            transport: RelayClient(relay: relay, deviceID: identityB.deviceID), trust: trust)
    }
    func clean() { cleanupWorkspaceTestStorage(directory) }
}

@Test func offlineChatConvergesThroughCiphertextQueueAndLostUploadResponse() async throws {
    let pair = try await SyncPair(); defer { pair.clean() }
    let chatsA = WorkspaceChatService(repository: pair.a, identity: pair.identityA)
    let conversation = try await chatsA.createConversation(commandID: UUID(), title: "Shared")
    let first = try await chatsA.sendMessage(commandID: UUID(), conversationID: conversation, content: "Секретный текст")
    await pair.relay.loseNextUploadResponse()
    await #expect(throws: CiphertextRelay.Failure.self) { try await pair.engineA.synchronize() }
    let reopenedA = try await workspaceTestRepository(url: pair.directory.appendingPathComponent("a.sqlite"))
    let restarted = WorkspaceSyncEngine(repository: reopenedA, identity: pair.identityA, cryptography: pair.cryptoA,
        transport: RelayClient(relay: pair.relay, deviceID: pair.identityA.deviceID), trust: pair.trust)
    try await restarted.synchronize()
    try await pair.engineB.synchronize()
    let chatsB = WorkspaceChatService(repository: pair.b, identity: pair.identityB)
    _ = try await chatsB.sendMessage(commandID: UUID(), conversationID: conversation, content: "From iPhone", replyToMessageID: first)
    _ = try await chatsA.sendMessage(commandID: UUID(), conversationID: conversation, content: "From Mac")
    try await pair.engineB.synchronize()
    try await restarted.synchronize()
    try await pair.engineB.synchronize()
    let left = WorkspaceMessageOrder.ordered(try await pair.a.records(BlotV3.Message.self, workspaceID: pair.identityA.workspaceID))
    let right = WorkspaceMessageOrder.ordered(try await pair.b.records(BlotV3.Message.self, workspaceID: pair.identityB.workspaceID))
    #expect(left == right && left.count == 3)
    #expect(await pair.relay.count() == 4)
    #expect(try await pair.a.pendingSyncChanges().isEmpty)
    #expect(try await pair.b.pendingSyncChanges().isEmpty)
    #expect(try await !String(decoding: pair.relay.bytes(), as: UTF8.self).contains("Секретный текст"))
}

@Test func fieldEditsMergeAndConcurrentAgentRevisionsRemainAvailable() async throws {
    let pair = try await SyncPair(); defer { pair.clean() }
    let agentA = WorkspaceAgentService(repository: pair.a, identity: pair.identityA)
    let agent = try await agentA.save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Base"))
    let conversation = try await WorkspaceChatService(repository: pair.a, identity: pair.identityA).createConversation(commandID: UUID(), title: "Before", agentID: agent)
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize()
    try await WorkspaceConversationService(repository: pair.a, identity: pair.identityA).update(commandID: UUID(), conversationID: conversation, expectedVersion: 1, title: "Renamed")
    try await WorkspaceConversationService(repository: pair.b, identity: pair.identityB).update(commandID: UUID(), conversationID: conversation, expectedVersion: 1, pinned: true)
    _ = try await agentA.save(commandID: UUID(), agentID: agent, expectedVersion: 1, draft: .init(name: "Worker", instructions: "Mac instructions"))
    _ = try await WorkspaceAgentService(repository: pair.b, identity: pair.identityB).save(commandID: UUID(), agentID: agent, expectedVersion: 1,
        draft: .init(name: "Worker", instructions: "Phone instructions"))
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize(); try await pair.engineA.synchronize()
    let left = try #require(try await pair.a.record(BlotV3.Conversation.self, id: conversation, workspaceID: pair.identityA.workspaceID))
    let right = try #require(try await pair.b.record(BlotV3.Conversation.self, id: conversation, workspaceID: pair.identityB.workspaceID))
    #expect(left == right && left.title == "Renamed" && left.pinned)
    for repository in [pair.a, pair.b] {
        let conflicts = try await repository.records(BlotV3.ConflictingRevision.self, workspaceID: pair.identityA.workspaceID)
        #expect(conflicts.count == 2 && conflicts.allSatisfy { !$0.resolved })
        #expect(conflicts.contains { $0.payloadJSON.contains("Mac instructions") })
        #expect(conflicts.contains { $0.payloadJSON.contains("Phone instructions") })
        #expect(try await repository.records(BlotV3.AgentConfigurationRevision.self, workspaceID: pair.identityA.workspaceID).count == 3)
    }
    let conflicts = try await pair.a.projection(identity: pair.identityA).conflicts
    let selected = try #require(conflicts.first { $0.payloadJSON.contains("Mac instructions") })
    await #expect(throws: WorkspaceStorageError.unresolvedConflict) {
        _ = try await WorkspaceTaskService(repository: pair.a, identity: pair.identityA).create(commandID: UUID(),
            conversationID: conversation, agentID: agent, goal: "Do work", executorDeviceID: pair.identityA.deviceID)
    }
    let third = try await workspaceTestRepository(url: pair.directory.appendingPathComponent("c.sqlite"))
    let thirdID = try await third.joinWorkspace(ownerID: pair.identityA.ownerID, workspaceID: pair.identityA.workspaceID)
    try await third.installReplicaSnapshot(pair.a.replicaSnapshot(identity: pair.identityA), identity: thirdID)
    #expect(try await third.projection(identity: thirdID).conflicts.count == 2)
    let resolution = WorkspaceConflictService(repository: pair.a, identity: pair.identityA)
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        try await resolution.resolve(commandID: UUID(), selectedRevisionID: selected.metadata.id, displayedRevisionIDs: [selected.metadata.id])
    }
    let resolveCommand = UUID()
    try await resolution.resolve(commandID: resolveCommand, selectedRevisionID: selected.metadata.id, displayedRevisionIDs: Set(conflicts.map(\.metadata.id)))
    try await resolution.resolve(commandID: resolveCommand, selectedRevisionID: selected.metadata.id, displayedRevisionIDs: Set(conflicts.map(\.metadata.id)))
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize()
    for (repository, identity) in [(pair.a, pair.identityA), (pair.b, pair.identityB)] {
        let projection = try await repository.projection(identity: identity)
        #expect(projection.conflicts.allSatisfy { $0.resolved })
        #expect(projection.agents.first { $0.metadata.id == agent }?.instructions == "Mac instructions")
    }
    _ = try await WorkspaceTaskService(repository: pair.a, identity: pair.identityA).create(commandID: UUID(),
        conversationID: conversation, agentID: agent, goal: "Do work", executorDeviceID: pair.identityA.deviceID)
}

@Test func deletionSurvivesAnOldSnapshotAndSequenceGapRollsBackCursor() async throws {
    let pair = try await SyncPair(); defer { pair.clean() }
    let chats = WorkspaceChatService(repository: pair.a, identity: pair.identityA)
    let conversation = try await chats.createConversation(commandID: UUID(), title: "Delete")
    _ = try await chats.sendMessage(commandID: UUID(), conversationID: conversation, content: "Temporary")
    let pending = try await pair.a.pendingSyncChanges()
    await #expect(throws: WorkspaceSyncError.sequenceGap) {
        try await pair.b.applySyncChanges([pending[1]], identity: pair.identityB, relayCursor: 2)
    }
    #expect(try await pair.b.relayCursor() == 0)
    #expect(try await pair.b.records(BlotV3.Message.self, workspaceID: pair.identityB.workspaceID).isEmpty)
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize()
    let old = try await pair.a.replicaSnapshot(identity: pair.identityA)
    try await WorkspaceConversationService(repository: pair.a, identity: pair.identityA).delete(commandID: UUID(), conversationID: conversation, expectedVersion: 1)
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize()
    try await pair.b.installReplicaSnapshot(old, identity: pair.identityB)
    #expect(try await pair.b.records(BlotV3.Conversation.self, workspaceID: pair.identityB.workspaceID).isEmpty)
    #expect(try await pair.b.searchMessages("Temporary", workspaceID: pair.identityB.workspaceID).isEmpty)
}

@Test func ciphertextTamperingAndUntrustedSignerFailBeforePersistence() async throws {
    let pair = try await SyncPair(); defer { pair.clean() }
    _ = try await WorkspaceChatService(repository: pair.a, identity: pair.identityA).createConversation(commandID: UUID(), title: "Private")
    let change = try #require(try await pair.a.pendingSyncChanges().first)
    let packet = try await pair.cryptoA.encrypt(change)
    var corrupted = packet.ciphertext
    corrupted[corrupted.startIndex] ^= 1
    let tampered = WorkspaceEncryptedPacket(kind: packet.kind, workspaceID: packet.workspaceID, originDeviceID: packet.originDeviceID,
        changeID: packet.changeID, sequence: packet.sequence, keyEpoch: packet.keyEpoch, ciphertext: corrupted, signature: packet.signature)
    let senderKey = try #require(pair.trust.keys[pair.identityA.deviceID])
    await #expect(throws: WorkspaceSyncError.invalidSignature) { _ = try await pair.cryptoB.decrypt(tampered, trustedSigningKey: senderKey) }
    await #expect(throws: WorkspaceSyncError.invalidSignature) { _ = try await pair.cryptoB.decrypt(packet, trustedSigningKey: P256.Signing.PrivateKey().publicKey.x963Representation) }
    #expect(try await pair.b.records(BlotV3.Conversation.self, workspaceID: pair.identityB.workspaceID).isEmpty)
}

@Test func streamingCoalescesOnlyBeforePublicationAndRecoveryBelongsToExecutor() async throws {
    let pair = try await SyncPair(); defer { pair.clean() }
    let chat = WorkspaceChatService(repository: pair.a, identity: pair.identityA)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Stream ownership")
    let sourceID = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Request")
    let source = try #require(try await pair.a.record(BlotV3.Message.self, id: sourceID, workspaceID: pair.identityA.workspaceID))
    let recorderA = WorkspaceResponseRecorder(repository: pair.a, identity: pair.identityA)
    let responseID = UUID()
    _ = try await recorderA.begin(id: responseID, replyingTo: source, agentID: nil)
    for _ in 0..<100 { _ = try await recorderA.append("part", to: responseID) }
    let before = try await pair.a.pendingSyncChanges().filter { $0.recordID == responseID }
    #expect(before.count == 1)
    #expect(before[0].version == 101)
    let snapshot = try await pair.a.replicaSnapshot(identity: pair.identityA)
    try await pair.b.installReplicaSnapshot(snapshot, identity: pair.identityB)
    let recorderB = WorkspaceResponseRecorder(repository: pair.b, identity: pair.identityB)
    try await recorderB.recoverInterruptedResponses()
    #expect(try await pair.b.record(BlotV3.Message.self, id: responseID, workspaceID: pair.identityB.workspaceID)?.delivery == .running)
    #expect(try await pair.b.pendingSyncChanges().isEmpty)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await recorderB.append("foreign", to: responseID) }
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await recorderB.finish(responseID, delivery: .canceled) }
    let claimed = try #require(try await pair.a.claimSyncChanges().first { $0.recordID == responseID })
    let packet = try await pair.a.cacheEncryptedOutboxPacket(pair.cryptoA.encrypt(claimed))
    _ = try await recorderA.append(" final", to: responseID)
    _ = try await recorderA.finish(responseID, delivery: .completed)
    let changes = try await pair.a.pendingSyncChanges().filter { $0.recordID == responseID }
    #expect(changes.count == 2 && changes[0] == claimed)
    #expect(changes[1].changedFields.contains("content") && changes[1].changedFields.contains("delivery"))
    #expect(try await pair.a.encryptedOutboxPacket(changeID: claimed.changeID) == packet)
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize()
    let final = try #require(try await pair.b.record(BlotV3.Message.self, id: responseID, workspaceID: pair.identityB.workspaceID))
    #expect(final.content == String(repeating: "part", count: 100) + " final")
    #expect(final.delivery == .completed && final.executorDeviceId == pair.identityA.deviceID)
}

@Test func offlineDuplicateAgentThreadsConvergeAsOneChatWithoutChangingExecutors() async throws {
    let pair = try await SyncPair(); defer { pair.clean() }
    let agent = try await WorkspaceAgentService(repository: pair.a, identity: pair.identityA).save(commandID: UUID(),
        draft: .init(name: "Agent", instructions: "Help"))
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize()
    let first = try await WorkspaceChatService(repository: pair.a, identity: pair.identityA).createConversation(commandID: UUID(),
        title: "Agent", agentID: agent, now: Date(timeIntervalSince1970: 10))
    let second = try await WorkspaceChatService(repository: pair.b, identity: pair.identityB).createConversation(commandID: UUID(),
        title: "Agent", agentID: agent, now: Date(timeIntervalSince1970: 20))
    let sourceID = try await WorkspaceChatService(repository: pair.b, identity: pair.identityB).sendMessage(commandID: UUID(),
        conversationID: second, content: "From phone")
    let source = try #require(try await pair.b.record(BlotV3.Message.self, id: sourceID, workspaceID: pair.identityB.workspaceID))
    let recorder = WorkspaceResponseRecorder(repository: pair.b, identity: pair.identityB)
    let responseID = UUID()
    _ = try await recorder.begin(id: responseID, replyingTo: source, agentID: agent)
    _ = try await recorder.finish(responseID, delivery: .completed, content: "Phone reply")
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize(); try await pair.engineA.synchronize()
    let left = try await pair.a.projection(identity: pair.identityA)
    let right = try await pair.b.projection(identity: pair.identityB)
    #expect(left.conversations.map(\.metadata.id) == [first])
    #expect(left.conversations == right.conversations && left.messages == right.messages)
    #expect(left.messages.allSatisfy { $0.conversationId == first })
    #expect(try await pair.a.record(BlotV3.Message.self, id: responseID, workspaceID: pair.identityA.workspaceID)?.conversationId == second)
    #expect(try await pair.a.record(BlotV3.Message.self, id: responseID, workspaceID: pair.identityA.workspaceID)?.executorDeviceId == pair.identityB.deviceID)
    _ = try await WorkspaceChatService(repository: pair.a, identity: pair.identityA).sendMessage(commandID: UUID(),
        conversationID: first, content: "Reply from Mac", replyToMessageID: responseID)
    try await pair.engineA.synchronize(); try await pair.engineB.synchronize()
    #expect(try await pair.b.projection(identity: pair.identityB).messages.count == 3)
}
