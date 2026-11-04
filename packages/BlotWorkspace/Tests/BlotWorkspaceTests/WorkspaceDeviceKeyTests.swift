import BlotDomain
import CryptoKit
import Foundation
import Testing
@testable import BlotWorkspace

private actor DeviceTestCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values.removeValue(forKey: name) }
}

@Test func deviceAgreementTransfersHistoryKeysOnlyToBoundRecipientAndPersists() async throws {
    let owner = UUID(), workspace = UUID()
    let firstID = WorkspaceIdentity(ownerID: owner, workspaceID: workspace, deviceID: UUID())
    let secondID = WorkspaceIdentity(ownerID: owner, workspaceID: workspace, deviceID: UUID())
    let firstStore = DeviceTestCredentials(), secondStore = DeviceTestCredentials()
    let first = try await WorkspaceDeviceKeys.open(identity: firstID, credentials: firstStore)
    let second = try await WorkspaceDeviceKeys.open(identity: secondID, credentials: secondStore)
    try await first.initializeWorkspace()
    let firstPublic = try await first.publicKeys()
    #expect(firstPublic.signingKey != firstPublic.encryptionKey)
    let secondPublic = try await second.publicKeys()
    let wrapped = try await first.wrapKeys(for: secondID.deviceID, encryptionKey: secondPublic.encryptionKey)
    let proof = try await first.signProof(domain: "BLOT-TEST-KEY-TRANSFER-1", ids: [workspace, secondID.deviceID], values: [wrapped])
    try WorkspaceDeviceKeys.verifyProof(proof, signingKey: firstPublic.signingKey, domain: "BLOT-TEST-KEY-TRANSFER-1", ids: [workspace, secondID.deviceID], values: [wrapped])
    #expect(throws: WorkspaceSyncError.invalidSignature) {
        try WorkspaceDeviceKeys.verifyProof(proof, signingKey: firstPublic.signingKey, domain: "BLOT-TEST-KEY-TRANSFER-1", ids: [workspace, firstID.deviceID], values: [wrapped])
    }
    try await second.acceptWrappedKeys(wrapped, signerID: firstID.deviceID, epoch: 1)
    let reopened = try await WorkspaceDeviceKeys.open(identity: secondID, credentials: secondStore)
    #expect(try await reopened.publicKeys() == secondPublic)
    #expect(try await reopened.currentEpoch() == 1)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let conversationID = UUID()
    let metadata = try BlotV3.RecordMetadata(id: conversationID, ownerId: owner, workspaceId: workspace, version: 1, createdAt: date, updatedAt: date)
    let conversation = try BlotV3.Conversation(metadata: metadata, title: "Encrypted history", mobileOwned: false, pinned: false, archived: false, kind: .direct)
    var vector = WorkspaceVersionVector(); vector.observe(firstID.deviceID, sequence: 1)
    let change = WorkspaceSyncChange(changeID: UUID(), workspaceID: workspace, ownerID: owner, originDeviceID: firstID.deviceID,
        sequence: 1, kind: "Conversation", recordID: conversationID, version: 1, payload: String(decoding: try WorkspaceCoding.encode(conversation), as: UTF8.self),
        deleted: false, vector: vector, changedFields: ["title"], occurredAt: date)
    let packet = try await first.cryptography().encrypt(change)
    #expect(try await reopened.cryptography().decrypt(packet, trustedSigningKey: firstPublic.signingKey) == change)
    let freshRecipient = try await WorkspaceDeviceKeys.open(identity: secondID, credentials: DeviceTestCredentials())
    // Different private agreement key cannot open a grant for the original installation.
    await #expect(throws: (any Error).self) { try await freshRecipient.acceptWrappedKeys(wrapped, signerID: firstID.deviceID, epoch: 1) }
    let wrongRecipient = WorkspaceIdentity(ownerID: owner, workspaceID: workspace, deviceID: UUID())
    let wrong = try await WorkspaceDeviceKeys.open(identity: wrongRecipient, credentials: DeviceTestCredentials())
    await #expect(throws: WorkspaceSyncError.identityMismatch) { try await wrong.acceptWrappedKeys(wrapped, signerID: firstID.deviceID, epoch: 1) }
}
