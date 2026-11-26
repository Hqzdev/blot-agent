import BlotDomain
import Foundation

public struct WorkspacePageDocument: Codable, Equatable, Sendable, Identifiable {
    public struct Block: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable { case text, table, metric, link }
        public var id: UUID
        public var kind: Kind
        public var title: String
        public var text: String
        public var columns: [String]
        public var rows: [[String]]
        public init(id: UUID = UUID(), kind: Kind = .text, title: String = "", text: String, columns: [String] = [], rows: [[String]] = []) {
            self.id = id; self.kind = kind; self.title = title; self.text = text; self.columns = columns; self.rows = rows
        }
    }
    public let format: String
    public let id: UUID
    public let revisionID: UUID
    public let parents: [UUID]
    public let updatedAt: Date
    public var title: String
    public var pinned: Bool
    public var archived: Bool
    public var blocks: [Block]
}

public struct WorkspacePageSummary: Identifiable, Sendable {
    public let document: WorkspacePageDocument
    public let conflicting: Bool
    public var id: UUID { document.id }
}

/// Pages are immutable JSON artifacts: existing encrypted file sync transfers revisions without new record kinds.
public actor WorkspacePageService {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceFileService
    private var mutating = false
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceFileService) {
        self.repository = repository; self.identity = identity; self.files = files
    }
    public func revisions(_ id: UUID? = nil) async throws -> [WorkspacePageDocument] {
        let artifacts = try await repository.projection(identity: identity).artifacts.filter {
            $0.mediaType == "application/json" && $0.name.hasPrefix("blot-page-") && (id == nil || $0.name.hasPrefix("blot-page-" + id!.uuidString + "-"))
        }
        var documents: [WorkspacePageDocument] = []
        for artifact in artifacts {
            let url = try await files.url(for: artifact.metadata.id)
            let data = try Data(contentsOf: url)
            guard data.count <= 128_000 else { throw WorkspaceStorageError.invalidRecord }
            let page = try JSONDecoder().decode(WorkspacePageDocument.self, from: data)
            guard page.format == "blot.page.v1", page.revisionID == artifact.metadata.id,
                  artifact.name == "blot-page-" + page.id.uuidString + "-" + page.revisionID.uuidString + ".json",
                  Set(page.parents).count == page.parents.count, !page.parents.contains(page.revisionID) else { throw WorkspaceStorageError.invalidRecord }
            try Self.validate(title: page.title, blocks: page.blocks)
            documents.append(page)
        }
        return documents.sorted { $0.updatedAt > $1.updatedAt }
    }
    public func list() async throws -> [WorkspacePageSummary] {
        let pages = try await revisions()
        return Dictionary(grouping: pages, by: \.id).values.compactMap { revisions in
            let superseded = Set(revisions.flatMap(\.parents))
            let heads = revisions.filter { !superseded.contains($0.revisionID) }
            guard let latest = heads.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
            return .init(document: latest, conflicting: heads.count > 1)
        }.sorted { $0.document.pinned != $1.document.pinned ? $0.document.pinned : $0.document.updatedAt > $1.document.updatedAt }
    }
    @discardableResult public func save(id: UUID = UUID(), revisionID: UUID = UUID(), expectedRevision: UUID?, title: String,
                                       blocks: [WorkspacePageDocument.Block], pinned: Bool = false, archived: Bool = false) async throws -> WorkspacePageDocument {
        guard !mutating else { throw WorkspaceStorageError.versionConflict }
        mutating = true; defer { mutating = false }
        try Self.validate(title: title, blocks: blocks)
        let current = try await revisions(id), superseded = Set(current.flatMap(\.parents))
        if let saved = current.first(where: { $0.revisionID == revisionID }) {
            guard saved.title == title, saved.blocks == blocks, saved.pinned == pinned, saved.archived == archived,
                  saved.parents == (expectedRevision.map { [$0] } ?? []) else { throw WorkspaceStorageError.commandConflict }
            return saved
        }
        let heads = current.filter { !superseded.contains($0.revisionID) }
        guard heads.count <= 1, heads.first?.revisionID == expectedRevision else { throw WorkspaceStorageError.versionConflict }
        let document = WorkspacePageDocument(format: "blot.page.v1", id: id, revisionID: revisionID, parents: expectedRevision.map { [$0] } ?? [],
            updatedAt: Date(), title: title, pinned: pinned, archived: archived, blocks: blocks)
        let data = try JSONEncoder().encode(document)
        guard data.count <= 128_000 else { throw WorkspaceStorageError.invalidParameters }
        _ = try await files.store(commandID: document.revisionID, name: "blot-page-" + id.uuidString + "-" + document.revisionID.uuidString + ".json", mediaType: "application/json", data: data)
        return document
    }
    public func export(_ document: WorkspacePageDocument) async throws -> URL { try await files.url(for: document.revisionID) }
    /// Restoring creates a new revision; history and concurrent branches remain intact.
    public func restore(pageID: UUID, revisionID: UUID, expectedHeads: Set<UUID>) async throws -> WorkspacePageDocument {
        guard !mutating else { throw WorkspaceStorageError.versionConflict }
        mutating = true; defer { mutating = false }
        let revisions = try await revisions(pageID), parents = Set(revisions.flatMap(\.parents))
        let heads = Set(revisions.filter { !parents.contains($0.revisionID) }.map(\.revisionID))
        guard heads == expectedHeads, let source = revisions.first(where: { $0.revisionID == revisionID }) else { throw WorkspaceStorageError.versionConflict }
        let document = WorkspacePageDocument(format: "blot.page.v1", id: pageID, revisionID: UUID(),
            parents: heads.sorted { $0.uuidString < $1.uuidString }, updatedAt: Date(), title: source.title,
            pinned: source.pinned, archived: false, blocks: source.blocks)
        let data = try JSONEncoder().encode(document)
        _ = try await files.store(commandID: document.revisionID, name: "blot-page-" + pageID.uuidString + "-" + document.revisionID.uuidString + ".json", mediaType: "application/json", data: data)
        return document
    }
    private static func validate(title: String, blocks: [WorkspacePageDocument.Block]) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf8.count <= 800, blocks.count <= 100,
              Set(blocks.map(\.id)).count == blocks.count else { throw WorkspaceStorageError.invalidParameters }
        for block in blocks {
            guard block.title.utf8.count <= 800, block.text.utf8.count <= 48_000, block.columns.count <= 50,
                  block.columns.allSatisfy({ $0.utf8.count <= 800 }),
                  block.kind != .table || !block.columns.isEmpty,
                  block.rows.count <= 1000, block.rows.allSatisfy({ $0.count == block.columns.count && $0.allSatisfy({ $0.utf8.count <= 4000 }) }) else { throw WorkspaceStorageError.invalidParameters }
            if block.kind == .link { _ = try WorkspaceBrowserURL.validated(block.text) }
        }
    }
}
