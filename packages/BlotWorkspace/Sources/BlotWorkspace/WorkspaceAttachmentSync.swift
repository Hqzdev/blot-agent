import BlotDomain
import CryptoKit
import Foundation

public struct WorkspaceEncryptedFileChunk: Codable, Equatable, Sendable {
    public let blobID: UUID
    public let index: Int
    public let count: Int
    public let ciphertext: Data
    public init(blobID: UUID, index: Int, count: Int, ciphertext: Data) {
        self.blobID = blobID; self.index = index; self.count = count; self.ciphertext = ciphertext
    }
}
public protocol WorkspaceAttachmentTransport: Sendable {
    func put(_ chunk: WorkspaceEncryptedFileChunk) async throws
    func get(blobID: UUID, index: Int) async throws -> WorkspaceEncryptedFileChunk
}
public struct WorkspaceCloudAttachmentTransport: WorkspaceAttachmentTransport {
    private let http: WorkspaceCloudHTTP
    private let authorization: any WorkspaceCloudAuthorization
    public init(http: WorkspaceCloudHTTP, authorization: any WorkspaceCloudAuthorization) { self.http = http; self.authorization = authorization }
    public func put(_ chunk: WorkspaceEncryptedFileChunk) async throws {
        try await http.empty(method: "PUT", path: ["v1", "relay", "blobs"], body: JSONEncoder().encode(chunk), accessToken: authorization.accessToken())
    }
    public func get(blobID: UUID, index: Int) async throws -> WorkspaceEncryptedFileChunk {
        try await http.request(WorkspaceEncryptedFileChunk.self, method: "GET", path: ["v1", "relay", "blobs", blobID.uuidString, String(index)], accessToken: authorization.accessToken())
    }
}

/// File metadata replicates separately. Interrupted downloads retain only verified ciphertext chunks.
public actor WorkspaceAttachmentSync {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceFileService
    private let cryptography: WorkspaceSyncCryptography
    private let transport: any WorkspaceAttachmentTransport
    private let cacheDirectory: URL

    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceFileService,
                cryptography: WorkspaceSyncCryptography, transport: any WorkspaceAttachmentTransport, cacheDirectory: URL) {
        self.repository = repository; self.identity = identity; self.files = files; self.cryptography = cryptography
        self.transport = transport; self.cacheDirectory = cacheDirectory
    }
    public func upload(artifactID: UUID) async throws {
        let data = try await files.data(for: artifactID)
        let artifact = try await files.bindEncryptionEpoch(cryptography.currentEpoch, artifactID: artifactID)
        let descriptor = try descriptor(artifact)
        guard data.count == descriptor.byteCount, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == descriptor.hash else {
            throw WorkspaceFileError.integrityMismatch
        }
        for index in 0..<descriptor.chunkCount {
            try _Concurrency.Task.checkCancellation()
            let start = index * WorkspaceAttachmentDescriptor.chunkBytes
            let end = min(data.count, start + WorkspaceAttachmentDescriptor.chunkBytes)
            let ciphertext = try await cryptography.encryptAttachmentChunk(data.subdata(in: start..<end), descriptor: descriptor, index: index)
            try await transport.put(.init(blobID: descriptor.blobID, index: index, count: descriptor.chunkCount, ciphertext: ciphertext))
        }
    }
    public func download(artifactID: UUID) async throws {
        guard let artifact = try await repository.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identity.workspaceID),
              artifact.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.missingRecord }
        let descriptor = try descriptor(artifact)
        var data = Data()
        for index in 0..<descriptor.chunkCount {
            try _Concurrency.Task.checkCancellation()
            let cache = try cacheURL(blobID: descriptor.blobID, index: index)
            let ciphertext: Data
            if let cached = try readCached(cache),
               (try? await cryptography.decryptAttachmentChunk(cached, descriptor: descriptor, index: index)) != nil {
                ciphertext = cached
            } else {
                let chunk = try await transport.get(blobID: descriptor.blobID, index: index)
                guard chunk.blobID == descriptor.blobID, chunk.index == index, chunk.count == descriptor.chunkCount else { throw WorkspaceSyncError.invalidChange }
                _ = try await cryptography.decryptAttachmentChunk(chunk.ciphertext, descriptor: descriptor, index: index)
                try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try chunk.ciphertext.write(to: cache, options: .atomic)
                ciphertext = chunk.ciphertext
            }
            data.append(try await cryptography.decryptAttachmentChunk(ciphertext, descriptor: descriptor, index: index))
        }
        try await files.installDownloaded(data, artifactID: artifactID)
        let folder = try cacheURL(blobID: descriptor.blobID, index: 0).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: folder)
    }
    private func descriptor(_ artifact: BlotV3.Artifact) throws -> WorkspaceAttachmentDescriptor {
        guard let epoch = artifact.encryptionEpoch else { throw WorkspaceSyncError.unknownKeyEpoch }
        return try WorkspaceAttachmentDescriptor(workspaceID: identity.workspaceID, artifactID: artifact.metadata.id,
            hash: artifact.hash, byteCount: artifact.byteCount, keyEpoch: Int64(epoch))
    }
    private func cacheURL(blobID: UUID, index: Int) throws -> URL {
        let root = cacheDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let result = root.appendingPathComponent(blobID.uuidString).appendingPathComponent(String(index)).standardizedFileURL.resolvingSymlinksInPath()
        guard result.path.hasPrefix(root.path + "/") else { throw WorkspaceFileError.unsafePath }
        return result
    }
    private func readCached(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: WorkspaceAttachmentDescriptor.chunkBytes + 29), data.count <= WorkspaceAttachmentDescriptor.chunkBytes + 28 else { return nil }
        return data
    }
}
