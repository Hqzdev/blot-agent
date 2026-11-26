import Foundation

/// Editable source and immutable render references travel through existing artifact sync.
public struct WorkspaceEditableDocument: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable { case markdown, pdf, table, presentation, text }
    public struct Slide: Codable, Equatable, Hashable, Sendable {
        public var title: String
        public var body: String
        public init(title: String, body: String) { self.title = title; self.body = body }
    }
    public let format: String
    public let id: UUID
    public var revisionID: UUID?
    public var parents: [UUID]
    public var exportArtifactID: UUID
    public var title: String
    public let kind: Kind
    public let sourceFileExtension: String?
    public let sourceMediaType: String?
    public var body: String
    public var columns: [String]
    public var rows: [[String]]
    public var slides: [Slide]

    public init(id: UUID, title: String, kind: Kind, body: String = "", columns: [String] = [], rows: [[String]] = [], slides: [Slide] = [],
                sourceFileExtension: String? = nil, sourceMediaType: String? = nil) {
        format = "blot.document.v1"; self.id = id; revisionID = nil; parents = []; exportArtifactID = id
        self.title = title; self.kind = kind; self.body = body; self.columns = columns; self.rows = rows; self.slides = slides
        self.sourceFileExtension = sourceFileExtension; self.sourceMediaType = sourceMediaType
    }
    public var fileExtension: String {
        if let sourceFileExtension { return sourceFileExtension }
        return switch kind { case .markdown: "md"; case .pdf, .presentation: "pdf"; case .table: "csv"; case .text: "txt" }
    }
    public var mediaType: String {
        if let sourceMediaType { return sourceMediaType }
        return switch kind { case .markdown: "text/markdown"; case .pdf, .presentation: "application/pdf"; case .table: "text/csv"; case .text: "text/plain" }
    }
    public var preview: String {
        switch kind {
        case .table: ([columns] + Array(rows.prefix(2))).map { $0.joined(separator: " · ") }.joined(separator: "\n")
        case .presentation: slides.prefix(3).map(\.title).joined(separator: "\n")
        default: String(body.prefix(240))
        }
    }
    func validate() throws {
        if let sourceFileExtension {
            guard sourceFileExtension.utf8.count <= 32, !sourceFileExtension.contains(where: { $0 == "/" || $0 == "\\" || $0.isNewline || $0 == "\0" }),
                  kind == .text || kind == .markdown else { throw WorkspaceStorageError.invalidParameters }
        }
        if let sourceMediaType {
            guard sourceMediaType.utf8.count <= 200, !sourceMediaType.contains(where: { $0.isNewline || $0 == "\0" }),
                  kind == .text || kind == .markdown else { throw WorkspaceStorageError.invalidParameters }
        }
        guard format == "blot.document.v1", !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 700, !title.contains(where: { $0.isNewline || $0 == "\0" }),
              body.utf8.count <= 500_000, Set(parents).count == parents.count else { throw WorkspaceStorageError.invalidParameters }
        guard try WorkspaceCoding.encode(self).count <= 2 * 1024 * 1024 else { throw WorkspaceFileError.tooLarge }
        if kind == .table {
            guard !columns.isEmpty, columns.count <= 100, rows.count <= 10_000,
                  rows.allSatisfy({ $0.count == columns.count }) else { throw WorkspaceStorageError.invalidParameters }
        }
        if kind == .presentation {
            guard (1...30).contains(slides.count), slides.allSatisfy({ $0.title.utf8.count <= 1000 && $0.body.utf8.count <= 10_000 }) else { throw WorkspaceStorageError.invalidParameters }
        }
    }
    public func rendered() throws -> Data {
        try validate()
        let writer = WorkspaceDocumentWriter()
        switch kind {
        case .markdown: return sourceFileExtension == nil ? writer.markdown(title: title, body: body) : Data(body.utf8)
        case .pdf: return try writer.pdf(title: title, body: body)
        case .text: return Data(body.utf8)
        case .table: return try writer.csv(headers: columns, rows: rows)
        case .presentation: return try WorkspacePresentationDocumentWriter().pdf(slides: slides.map { .init(title: $0.title, body: $0.body) })
        }
    }
    static func generated(id: UUID, arguments: ChatJSON) throws -> Self {
        let fields = arguments.mcpFields
        guard let name = fields["name"]?.mcpString, let format = fields["format"]?.mcpString else { throw WorkspaceToolError.invalidArguments }
        switch format {
        case "markdown", "pdf":
            guard let body = fields["content"]?.mcpString else { throw WorkspaceToolError.invalidArguments }
            return .init(id: id, title: name, kind: format == "pdf" ? .pdf : .markdown, body: body)
        case "presentation":
            guard let value = fields["slides"] else { throw WorkspaceToolError.invalidArguments }
            return .init(id: id, title: name, kind: .presentation, slides: try JSONDecoder().decode([Slide].self, from: JSONEncoder().encode(value)))
        case "csv":
            if let headers = fields["headers"], let rows = fields["rows"] {
                return .init(id: id, title: name, kind: .table,
                    columns: try JSONDecoder().decode([String].self, from: JSONEncoder().encode(headers)),
                    rows: try JSONDecoder().decode([[String]].self, from: JSONEncoder().encode(rows)))
            }
            return .init(id: id, title: name, kind: .table, columns: ["Content"], rows: (fields["content"]?.mcpString ?? "").components(separatedBy: .newlines).map { [$0] })
        default: throw WorkspaceToolError.invalidArguments
        }
    }
    public static func isInternalArtifact(name: String) -> Bool {
        name.range(of: #"^blot-(?:document|render)-[A-Fa-f0-9-]{36}-[A-Fa-f0-9-]{36}(?:\.[^./\\\s]{1,32})?$"#, options: .regularExpression) != nil
    }
}
