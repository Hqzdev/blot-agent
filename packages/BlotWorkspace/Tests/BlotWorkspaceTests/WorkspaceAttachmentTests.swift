import BlotDomain
import CryptoKit
import Foundation
import Testing
@testable import BlotWorkspace

private actor AttachmentRelay: WorkspaceAttachmentTransport {
    enum Failure: Error { case disconnected }
    private var chunks: [UUID: [Int: WorkspaceEncryptedFileChunk]] = [:]
    private var gets: [Int: Int] = [:]
    private var failIndex: Int?
    func disconnectOnce(at index: Int) { failIndex = index }
    func put(_ chunk: WorkspaceEncryptedFileChunk) throws {
        if let old = chunks[chunk.blobID]?[chunk.index], old != chunk { throw WorkspaceSyncError.replayConflict }
        chunks[chunk.blobID, default: [:]][chunk.index] = chunk
    }
    func get(blobID: UUID, index: Int) throws -> WorkspaceEncryptedFileChunk {
        gets[index, default: 0] += 1
        if failIndex == index { failIndex = nil; throw Failure.disconnected }
        guard let chunk = chunks[blobID]?[index] else { throw Failure.disconnected }
        return chunk
    }
    func count() -> Int { chunks.values.reduce(0) { $0 + $1.count } }
    func fetches(index: Int) -> Int { gets[index] ?? 0 }
    func bytes() throws -> Data { try JSONEncoder().encode(chunks.values.flatMap(\.values)) }
}

@Test func encryptedAttachmentsResumeAcrossReopenAndVerifyBeforeInstallation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let a = try await workspaceTestRepository(url: directory.appendingPathComponent("a.sqlite"))
    let b = try await workspaceTestRepository(url: directory.appendingPathComponent("b.sqlite"))
    let identityA = try await a.localIdentity()
    let identityB = try await b.joinWorkspace(ownerID: identityA.ownerID, workspaceID: identityA.workspaceID)
    let filesA = WorkspaceFileService(repository: a, identity: identityA, directory: directory.appendingPathComponent("files-a"))
    let filesB = WorkspaceFileService(repository: b, identity: identityB, directory: directory.appendingPathComponent("files-b"))
    let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    let cryptoA = try WorkspaceSyncCryptography(identity: identityA, signingPrivateKey: P256.Signing.PrivateKey().rawRepresentation, epochKeys: [1: key], currentEpoch: 1)
    let cryptoB = try WorkspaceSyncCryptography(identity: identityB, signingPrivateKey: P256.Signing.PrivateKey().rawRepresentation, epochKeys: [1: key], currentEpoch: 1)
    let secret = "SECRET-ATTACHMENT-MATERIAL-DO-NOT-LOG\n"
    let data = Data(String(repeating: secret, count: 13_000).utf8)
    let artifactID = try await filesA.store(commandID: UUID(), name: "notes.txt", mediaType: "text/plain", data: data)
    let relay = AttachmentRelay()
    let upload = WorkspaceAttachmentSync(repository: a, identity: identityA, files: filesA, cryptography: cryptoA, transport: relay, cacheDirectory: directory.appendingPathComponent("cache-a"))
    try await upload.upload(artifactID: artifactID)
    try await upload.upload(artifactID: artifactID)
    #expect(await relay.count() == 3)
    #expect(try await !String(decoding: relay.bytes(), as: UTF8.self).contains(secret))
    try await b.installReplicaSnapshot(a.replicaSnapshot(identity: identityA), identity: identityB)
    let cacheB = directory.appendingPathComponent("cache-b")
    let download = WorkspaceAttachmentSync(repository: b, identity: identityB, files: filesB, cryptography: cryptoB, transport: relay, cacheDirectory: cacheB)
    await relay.disconnectOnce(at: 1)
    await #expect(throws: AttachmentRelay.Failure.disconnected) { try await download.download(artifactID: artifactID) }
    #expect(await relay.fetches(index: 0) == 1)
    await #expect(throws: (any Error).self) { _ = try await filesB.url(for: artifactID) }
    let reopened = try await workspaceTestRepository(url: directory.appendingPathComponent("b.sqlite"))
    let reopenedFiles = WorkspaceFileService(repository: reopened, identity: identityB, directory: directory.appendingPathComponent("files-b"))
    let resumed = WorkspaceAttachmentSync(repository: reopened, identity: identityB, files: reopenedFiles, cryptography: cryptoB, transport: relay, cacheDirectory: cacheB)
    try await resumed.download(artifactID: artifactID)
    #expect(await relay.fetches(index: 0) == 1)
    #expect(await relay.fetches(index: 1) == 2)
    #expect(try await reopenedFiles.data(for: artifactID) == data)
    let artifact = try #require(try await a.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identityA.workspaceID))
    let descriptor = try WorkspaceAttachmentDescriptor(workspaceID: identityA.workspaceID, artifactID: artifactID, hash: artifact.hash, byteCount: data.count, keyEpoch: 1)
    let chunk = try await relay.get(blobID: descriptor.blobID, index: 0)
    await #expect(throws: WorkspaceSyncError.invalidChange) { _ = try await cryptoB.decryptAttachmentChunk(chunk.ciphertext, descriptor: descriptor, index: 1) }
    var tampered = chunk.ciphertext; tampered[tampered.count - 1] ^= 1
    await #expect(throws: (any Error).self) { _ = try await cryptoB.decryptAttachmentChunk(tampered, descriptor: descriptor, index: 0) }
    await #expect(throws: WorkspaceFileError.integrityMismatch) { try await reopenedFiles.installDownloaded(Data("wrong".utf8), artifactID: artifactID) }
}
