import BlotDomain
import Foundation

/// Local files and memory candidates are the portable tools available without a Google connection.
public struct WorkspaceLocalTools: WorkspaceToolExecuting {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceFileService
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceFileService) {
        self.repository = repository; self.identity = identity; self.files = files
    }
    public var definitions: [ChatToolDefinition] {
        [definition("file_read", "Read a file explicitly attached to this user message.", properties: ["artifact_id": string], required: ["artifact_id"]),
         definition("document_create", "Create a Markdown, PDF or CSV result in the workspace.", properties: ["name": string,
            "format": .object(["type": .string("string"), "enum": .array([.string("markdown"), .string("pdf"), .string("csv")])]),
            "content": string], required: ["name", "format", "content"]),
         definition("memory_candidate", "Propose a memory from this conversation for user review. It remains unapproved.",
            properties: ["content": string], required: ["content"])]
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        try _Concurrency.Task.checkCancellation()
        guard case .object(let fields) = call.arguments,
              let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
              source.metadata.ownerId == identity.ownerID else { throw WorkspaceToolError.invalidArguments }
        switch call.name {
        case "file_read":
            guard case .string(let rawID) = fields["artifact_id"], let id = UUID(uuidString: rawID), source.artifactIds.contains(id) else {
                throw WorkspaceStorageError.permissionDenied
            }
            return .object(["content": .string(try await files.text(for: id))])
        case "document_create":
            guard case .string(let name) = fields["name"], case .string(let format) = fields["format"],
                  case .string(let content) = fields["content"] else { throw WorkspaceToolError.invalidArguments }
            let writer = WorkspaceDocumentWriter()
            let data: Data
            let mediaType: String
            let suffix: String
            switch format {
            case "markdown": data = writer.markdown(title: name, body: content); mediaType = "text/markdown"; suffix = "md"
            case "pdf": data = try writer.pdf(title: name, body: content); mediaType = "application/pdf"; suffix = "pdf"
            case "csv":
                data = try writer.csv(headers: ["Content"], rows: content.components(separatedBy: .newlines).map { [$0] })
                mediaType = "text/csv"; suffix = "csv"
            default: throw WorkspaceToolError.invalidArguments
            }
            let safeName = String(name.filter { $0 != "/" && $0 != "\\" && !$0.isNewline }.prefix(120))
            guard !safeName.isEmpty else { throw WorkspaceToolError.invalidArguments }
            let id = try await files.store(commandID: commandID(call, source: context.sourceMessageID),
                name: safeName + "." + suffix, mediaType: mediaType, data: data)
            return .object(["artifact_id": .string(id.uuidString), "name": .string(safeName + "." + suffix)])
        case "memory_candidate":
            guard case .string(let content) = fields["content"] else { throw WorkspaceToolError.invalidArguments }
            let id = try await WorkspaceMemoryService(repository: repository, identity: identity).create(
                commandID: commandID(call, source: context.sourceMessageID), content: content, sourceID: context.sourceMessageID, candidate: true)
            return .object(["candidate_id": .string(id.uuidString), "state": .string("waiting_user_review")])
        default: throw WorkspaceToolError.unknownTool
        }
    }
    private var string: ChatJSON { .object(["type": .string("string")]) }
    private func definition(_ name: String, _ description: String, properties: [String: ChatJSON], required: [String]) -> ChatToolDefinition {
        .init(name: name, description: description, parameters: .object(["type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(ChatJSON.string)), "additionalProperties": .bool(false)]))
    }
    private func commandID(_ call: ChatToolCall, source: UUID) -> UUID {
        WorkspaceLogicalID.make(kind: "LocalTool", workspaceID: identity.workspaceID, parts: [source.uuidString, call.id])
    }
}
