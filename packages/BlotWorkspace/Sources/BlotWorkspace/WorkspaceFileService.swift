import BlotDomain
import CryptoKit
import Foundation
import PDFKit

public enum WorkspaceFileError: Error, Equatable, Sendable {
    case unsupportedType, tooLarge, invalidText, missingFile, integrityMismatch, unsafePath, unreadablePDF
}

/// Content-addressed files are durable before metadata commits; source paths never enter replication.
public actor WorkspaceFileService {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let directory: URL
    private let maximumBytes: Int
    private static let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "tsv", "json", "swift", "java", "py", "js", "ts", "tsx", "jsx", "html", "css", "c", "cpp", "h", "rs", "go", "sh", "yaml", "yml", "sql", "kt", "rb", "toml", "xml", "log"]

    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, directory: URL, maximumBytes: Int = 32 * 1024 * 1024) {
        self.repository = repository; self.identity = identity; self.directory = directory; self.maximumBytes = maximumBytes
    }

    public nonisolated static func attachmentCommandID(sendCommandID: UUID, index: Int) -> UUID {
        WorkspaceLogicalID.make(kind: "MessageAttachment", workspaceID: sendCommandID, parts: [String(index)])
    }

    public func importFile(commandID: UUID, source: URL) async throws -> UUID {
        let ext = source.pathExtension.lowercased()
        guard ext == "pdf" || Self.textExtensions.contains(ext) else { throw WorkspaceFileError.unsupportedType }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard data.count <= maximumBytes - chunk.count else { throw WorkspaceFileError.tooLarge }
            data.append(chunk)
        }
        if ext != "pdf", String(data: data, encoding: .utf8) == nil { throw WorkspaceFileError.invalidText }
        if ext == "pdf" { _ = try Self.pdfText(data, maximumCharacters: 1) }
        return try await store(commandID: commandID, name: source.lastPathComponent, mediaType: Self.mediaType(ext), data: data)
    }

    public func store(commandID: UUID, name: String, mediaType: String, data: Data, taskID: UUID? = nil) async throws -> UUID {
        guard !name.isEmpty, !name.contains(where: { $0.isNewline }), data.count <= maximumBytes else { throw WorkspaceFileError.tooLarge }
        let hash = Self.digest(data)
        let relativePath = String(hash.prefix(2)) + "/" + hash + "." + Self.fileExtension(mediaType)
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
        guard let artifact = try await repository.record(BlotV3.Artifact.self, id: artifactID, workspaceID: identity.workspaceID) else {
            throw WorkspaceStorageError.missingRecord
        }
        let url = try safeURL(artifact.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw WorkspaceFileError.missingFile }
        let data = try boundedData(at: url)
        guard data.count == artifact.byteCount, Self.digest(data) == artifact.hash else { throw WorkspaceFileError.integrityMismatch }
        return url
    }

    public func text(for artifactID: UUID, maximumCharacters: Int = 48_000) async throws -> String {
        guard maximumCharacters > 0 else { throw WorkspaceStorageError.invalidParameters }
        let url = try await url(for: artifactID)
        let data = try boundedData(at: url)
        if url.pathExtension == "pdf" { return try Self.pdfText(data, maximumCharacters: maximumCharacters) }
        guard let text = String(data: data, encoding: .utf8) else { throw WorkspaceFileError.invalidText }
        return text.count > maximumCharacters ? String(text.prefix(maximumCharacters)) + "\n[Truncated]" : text
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

    private func boundedData(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard data.count <= maximumBytes - chunk.count else { throw WorkspaceFileError.tooLarge }
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

    private static func pdfText(_ data: Data, maximumCharacters: Int) throws -> String {
        guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount <= 1_000 else { throw WorkspaceFileError.unreadablePDF }
        var result = ""
        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result += "[Page \(index + 1)]\n" + text + "\n"
            if result.count >= maximumCharacters { return String(result.prefix(maximumCharacters)) + "\n[Truncated]" }
        }
        guard !result.isEmpty else { throw WorkspaceFileError.unreadablePDF }
        return result
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func mediaType(_ ext: String) -> String {
        switch ext {
        case "pdf": "application/pdf"
        case "json": "application/json"
        case "csv", "tsv": "text/csv"
        case "md", "markdown": "text/markdown"
        default: "text/plain"
        }
    }
    private static func fileExtension(_ mediaType: String) -> String {
        switch mediaType {
        case "application/pdf": "pdf"
        case "application/json": "json"
        case "text/csv": "csv"
        case "text/markdown": "md"
        default: "txt"
        }
    }
}
