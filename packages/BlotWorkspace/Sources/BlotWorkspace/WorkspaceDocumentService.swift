import BlotDomain
import Foundation

/// Sources and renders are immutable revisions; old clients keep reading the original file.
public actor WorkspaceDocumentService {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceFileService
    private var mutating = false
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceFileService) {
        self.repository = repository; self.identity = identity; self.files = files
    }
    private func prefix(_ id: UUID) -> String { "blot-document-" + id.uuidString + "-" }
    private func revisions(_ id: UUID) async throws -> [WorkspaceEditableDocument] {
        var result: [WorkspaceEditableDocument] = []
        let artifacts = try await repository.projection(identity: identity).artifacts.filter { $0.name.hasPrefix(prefix(id)) && $0.mediaType == "application/json" }
        for artifact in artifacts {
            guard artifact.byteCount <= 2 * 1024 * 1024 else { throw WorkspaceStorageError.invalidRecord }
            let value = try JSONDecoder().decode(WorkspaceEditableDocument.self, from: try await files.data(for: artifact.metadata.id))
            guard value.format == "blot.document.v1", value.id == id, value.revisionID == artifact.metadata.id,
                  artifact.name == prefix(id) + artifact.metadata.id.uuidString + ".json",
                  !value.parents.contains(artifact.metadata.id), Set(value.parents).count == value.parents.count else { throw WorkspaceStorageError.invalidRecord }
            try value.validate()
            result.append(value)
        }
        return result
    }
    public func load(_ id: UUID) async throws -> WorkspaceEditableDocument? {
        let revisions = try await revisions(id), parents = Set(revisions.flatMap(\.parents))
        let heads = revisions.filter { !parents.contains($0.revisionID!) }
        guard heads.count <= 1 else { throw WorkspaceStorageError.versionConflict }
        if let current = heads.first { return current }
        let projection = try await repository.projection(identity: identity)
        guard let artifact = projection.artifacts.first(where: { $0.metadata.id == id }) else { throw WorkspaceStorageError.missingRecord }
        // Recover the exact structured input of previously generated files, including slide boundaries.
        for step in projection.modelSteps {
            guard let raw = step.toolCallsJSON, let calls = try? JSONDecoder().decode([ChatToolCall].self, from: Data(raw.utf8)) else { continue }
            for call in calls where call.name == "document_create" {
                let generatedID = WorkspaceLogicalID.make(kind: "LocalTool", workspaceID: identity.workspaceID, parts: [step.sourceMessageId.uuidString, call.id])
                if generatedID == id { return try .generated(id: id, arguments: call.arguments) }
            }
        }
        if !WorkspaceEditableDocument.isInternalArtifact(name: artifact.name), WorkspaceTextFileFormat.accepts(name: artifact.name, mediaType: artifact.mediaType) {
            guard artifact.byteCount <= 2 * 1024 * 1024 else { throw WorkspaceFileError.tooLarge }
            guard let text = WorkspaceTextFileFormat.decode(try await files.data(for: id)) else { return nil }
            guard text.utf8.count <= 500_000 else { return nil }
            let title = (artifact.name as NSString).deletingPathExtension
            if artifact.mediaType == "text/csv" {
                let rows = try WorkspaceCSV().rows(text)
                guard let columns = rows.first, rows.allSatisfy({ $0.count == columns.count }) else { throw WorkspaceStorageError.invalidParameters }
                return .init(id: id, title: title, kind: .table, columns: columns, rows: Array(rows.dropFirst()))
            }
            // Preserve existing Markdown verbatim until an explicit edit/save.
            let ext = (artifact.name as NSString).pathExtension
            let markdown = artifact.mediaType == "text/markdown" || ["md", "markdown"].contains(ext.lowercased())
            return .init(id: id, title: title, kind: markdown ? .markdown : .text, body: text,
                sourceFileExtension: ext, sourceMediaType: artifact.mediaType)
        }
        return nil
    }
    public func preview(_ document: WorkspaceEditableDocument) async throws -> URL {
        try await files.preview(document.rendered(), mediaType: document.mediaType)
    }
    public func register(_ source: WorkspaceEditableDocument) async throws {
        try source.validate()
        let revisionID = WorkspaceLogicalID.make(kind: "DocumentSource", workspaceID: identity.workspaceID, parts: [source.id.uuidString])
        var revision = source; revision.revisionID = revisionID
        _ = try await files.store(commandID: revisionID, name: prefix(source.id) + revisionID.uuidString + ".json", mediaType: "application/json", data: WorkspaceCoding.encode(revision))
    }
    public func save(_ draft: WorkspaceEditableDocument, commandID: UUID) async throws -> WorkspaceEditableDocument {
        guard !mutating else { throw WorkspaceStorageError.versionConflict }
        mutating = true; defer { mutating = false }
        let command = try WorkspaceCommand(type: "document.save", workspaceID: identity.workspaceID, payload: draft).data()
        if try await repository.hasReceipt(commandID: commandID, command: command) {
            guard let saved = try await revisions(draft.id).first(where: { $0.revisionID == commandID }) else { throw WorkspaceStorageError.missingRecord }
            return saved
        }
        guard let current = try await load(draft.id), current.revisionID == draft.revisionID,
              current.kind == draft.kind, current.exportArtifactID == draft.exportArtifactID,
              current.sourceFileExtension == draft.sourceFileExtension, current.sourceMediaType == draft.sourceMediaType else { throw WorkspaceStorageError.versionConflict }
        let known = Set(try await revisions(draft.id).compactMap(\.revisionID))
        let data = try draft.rendered()
        var saved = draft
        saved.revisionID = commandID; saved.parents = current.revisionID.map { [$0] } ?? []
        saved.exportArtifactID = WorkspaceLogicalID.make(kind: "DocumentRender", workspaceID: identity.workspaceID, parts: [commandID.uuidString])
        let json = try JSONEncoder().encode(saved)
        guard json.count <= 2 * 1024 * 1024 else { throw WorkspaceFileError.tooLarge }
        let render = try await files.stage(data, mediaType: draft.mediaType)
        let source = try await files.stage(json, mediaType: "application/json")
        let originalID = draft.id, revisionID = commandID, exportID = saved.exportArtifactID
        let suffix = draft.fileExtension.isEmpty ? "" : "." + draft.fileExtension
        let sourcePrefix = prefix(draft.id), name = "blot-render-" + draft.id.uuidString + "-" + commandID.uuidString + suffix
        let type = draft.mediaType
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            _ = try tx.require(BlotV3.Artifact.self, id: originalID)
            let nowKnown = Set(try tx.records(BlotV3.Artifact.self).filter { $0.name.hasPrefix(sourcePrefix) }.map(\.metadata.id))
            guard nowKnown == known else { throw WorkspaceStorageError.versionConflict }
            try tx.put(BlotV3.Artifact(metadata: tx.metadata(id: exportID, now: Date()), execution: nil, name: name,
                mediaType: type, byteCount: render.byteCount, hash: render.hash, relativePath: render.relativePath), expectedVersion: 0)
            try tx.put(BlotV3.Artifact(metadata: tx.metadata(id: revisionID, now: Date()), execution: nil, name: sourcePrefix + revisionID.uuidString + ".json",
                mediaType: "application/json", byteCount: source.byteCount, hash: source.hash, relativePath: source.relativePath), expectedVersion: 0)
            return revisionID
        }
        return saved
    }
}
