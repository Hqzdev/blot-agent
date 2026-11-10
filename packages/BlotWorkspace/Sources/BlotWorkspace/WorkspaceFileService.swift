import BlotDomain
import CryptoKit
import Foundation

public enum WorkspaceFileError: Error, Equatable, Sendable {
    case unsupportedType, tooLarge, invalidText, missingFile, integrityMismatch, unsafePath, unreadablePDF, unreadableImage, recognitionFailed, noRecognizableText
}

/// Content-addressed files are durable before metadata commits; source paths never enter replication.
public actor WorkspaceFileService {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let directory: URL
    private let maximumBytes: Int
    private let extractor: WorkspaceFileTextExtractor

    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, directory: URL, maximumBytes: Int = 32 * 1024 * 1024,
                recognizer: any WorkspaceTextRecognizing = WorkspaceVisionTextRecognizer()) {
        self.repository = repository; self.identity = identity; self.directory = directory; self.maximumBytes = max(0, maximumBytes)
        extractor = WorkspaceFileTextExtractor(recognizer: recognizer)
    }

    public nonisolated static func attachmentCommandID(sendCommandID: UUID, index: Int) -> UUID {
        WorkspaceLogicalID.make(kind: "MessageAttachment", workspaceID: sendCommandID, parts: [String(index)])
    }

    public func importFile(commandID: UUID, source: URL) async throws -> UUID {
        let mediaType = try WorkspaceFileFormat.mediaType(forExtension: source.pathExtension)
        let data = try boundedData(at: source)
        try extractor.validate(data, mediaType: mediaType)
        return try await store(commandID: commandID, name: source.lastPathComponent, mediaType: mediaType, data: data)
    }

    public func store(commandID: UUID, name: String, mediaType: String, data: Data, taskID: UUID? = nil) async throws -> UUID {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 800,
              !name.contains(where: { $0.isNewline || $0 == "/" || $0 == "\\" || $0 == "\0" }) else { throw WorkspaceStorageError.invalidParameters }
        guard data.count <= maximumBytes else { throw WorkspaceFileError.tooLarge }
        try _Concurrency.Task.checkCancellation()
        let hash = Self.digest(data)
        let relativePath = String(hash.prefix(2)) + "/" + hash + "." + WorkspaceFileFormat.fileExtension(mediaType)
        let destination = try safeURL(relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard Self.digest(try boundedData(at: destination)) == hash else { throw WorkspaceFileError.integrityMismatch }
        } else { try data.write(to: destination, options: .atomic) }
        struct Input: Encodable { let name: String; let mediaType: String; let hash: String; let byteCount: Int; let taskID: UUID? }
        let command = try WorkspaceCommand(type: "artifact.store", workspaceID: identity.workspaceID,
            payload: Input(name: name, mediaType: mediaType, hash: hash, byteCount: data.count, taskID: taskID)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let execution = try taskID.map { try tx.require(BlotV3.Task.self, id: $0).execution }
            let artifact = try BlotV3.Artifact(metadata: tx.metadata(id: commandID, now: Date()), execution: execution, name: name,
                mediaType: mediaType, byteCount: data.count, hash: hash, relativePath: relativePath)
            try tx.put(artifact, expectedVersion: 0)
            return commandID
        }
    }

    public func url(for artifactID: UUID) async throws -> URL {
        guard let artifact = try await repository.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identity.workspaceID), artifact.metadata.ownerId == identity.ownerID else {
            throw WorkspaceStorageError.missingRecord
        }
        let url = try safeURL(artifact.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw WorkspaceFileError.missingFile }
        let data = try boundedData(at: url)
        guard data.count == artifact.byteCount, Self.digest(data) == artifact.hash else { throw WorkspaceFileError.integrityMismatch }
        return url
    }

    public func text(for artifactID: UUID, maximumCharacters: Int = 48_000) async throws -> String {
        let result = try await read(artifactID, maximumCharacters: maximumCharacters)
        return result.content + (result.truncated ? "\n[Truncated]" : "")
    }

    public func read(_ artifactID: UUID, startPage: Int = 1, pageCount: Int = 20, maximumCharacters: Int = 48_000) async throws -> WorkspaceExtractedText {
        guard (1...1_000).contains(startPage), (1...20).contains(pageCount), (1...48_000).contains(maximumCharacters) else { throw WorkspaceStorageError.invalidParameters }
        guard let artifact = try await repository.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identity.workspaceID),
              artifact.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.missingRecord }
        // Validate the original on every read, including cache hits and restored replicas.
        let data = try await self.data(for: artifactID)
        try _Concurrency.Task.checkCancellation()
        let key = Self.digest(Data((artifact.hash + "|" + artifact.mediaType + "|" + String(startPage) + "|" + String(pageCount)).utf8))
        let cacheURL = try safeURL("ExtractedText/v1/" + key + ".json")
        if let cached = try? boundedData(at: cacheURL, limit: 1024 * 1024),
           let result = try? WorkspaceCoding.decode(WorkspaceExtractedText.self, from: cached), result.startPage == startPage,
           (startPage...1_000).contains(result.totalPages), result.content.count <= 48_000,
           result.nextPage.map({ $0 > startPage && $0 <= result.totalPages }) ?? true {
            return try result.limited(to: maximumCharacters)
        }
        let result = try extractor.extract(data, mediaType: artifact.mediaType, startPage: startPage, pageCount: pageCount)
        try _Concurrency.Task.checkCancellation()
        // Cache is disposable. Failing to cache must not make a readable file unavailable.
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let encoded = try? WorkspaceCoding.encode(result) { try? encoded.write(to: cacheURL, options: .atomic) }
        return try result.limited(to: maximumCharacters)
    }

    public func data(for artifactID: UUID) async throws -> Data {
        guard let artifact = try await repository.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identity.workspaceID),
              artifact.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.missingRecord }
        let data = try boundedData(at: safeURL(artifact.relativePath))
        guard data.count == artifact.byteCount, Self.digest(data) == artifact.hash else { throw WorkspaceFileError.integrityMismatch }
        return data
    }

    public func installDownloaded(_ data: Data, artifactID: UUID) async throws {
        guard let artifact = try await repository.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identity.workspaceID),
              artifact.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.missingRecord }
        guard data.count <= maximumBytes, data.count == artifact.byteCount, Self.digest(data) == artifact.hash else { throw WorkspaceFileError.integrityMismatch }
        let destination = try safeURL(artifact.relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    public func bindEncryptionEpoch(_ epoch: Int64, artifactID: UUID) async throws -> BlotV3.Artifact {
        guard epoch > 0, let value = Int(exactly: epoch) else { throw WorkspaceSyncError.unknownKeyEpoch }
        struct Input: Encodable { let artifactID: UUID; let epoch: Int64 }
        let command = try WorkspaceCommand(type: "artifact.bind-encryption", workspaceID: identity.workspaceID, payload: Input(artifactID: artifactID, epoch: epoch)).data()
        let commandID = WorkspaceLogicalID.make(kind: "ArtifactEncryption", workspaceID: identity.workspaceID, parts: [artifactID.uuidString, String(epoch)])
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let old = try tx.require(BlotV3.Artifact.self, id: artifactID)
            if old.encryptionEpoch != nil { return artifactID }
            let updated = try BlotV3.Artifact(metadata: tx.metadata(id: artifactID, now: Date(), replacing: old.metadata), execution: old.execution,
                name: old.name, mediaType: old.mediaType, byteCount: old.byteCount, hash: old.hash, relativePath: old.relativePath, encryptionEpoch: value)
            try tx.put(updated, expectedVersion: old.metadata.version)
            return artifactID
        }
        guard let artifact = try await repository.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identity.workspaceID) else { throw WorkspaceStorageError.missingRecord }
        return artifact
    }

    private func boundedData(at url: URL, limit: Int? = nil) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw WorkspaceFileError.missingFile }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try _Concurrency.Task.checkCancellation()
            guard data.count <= (limit ?? maximumBytes) - chunk.count else { throw WorkspaceFileError.tooLarge }
            data.append(chunk)
        }
        return data
    }

    private func safeURL(_ relativePath: String) throws -> URL {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains(".."), candidate.path.hasPrefix(root.path + "/") else {
            throw WorkspaceFileError.unsafePath
        }
        return candidate
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
