import BlotDomain
import Foundation

/// Skill discovery and enqueueing are internal capabilities, separate from external tool permissions.
public struct WorkspaceSkillTools: WorkspaceToolExecuting {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }
    public var definitions: [ChatToolDefinition] {
        let string: ChatJSON = .object(["type": .string("string")])
        let pair: ChatJSON = .object(["type": .string("object"), "properties": .object(["name": string, "value": string]),
            "required": .array([.string("name"), .string("value")]), "additionalProperties": .bool(false)])
        return [definition("skill_list", "List assigned saved skills and their required parameters. Use offset for further pages.",
                    properties: ["offset": .object(["type": .string("integer")])], required: []),
                definition("skill_run", "Queue an assigned skill as a task. This does not mean execution has completed.",
                    properties: ["skill_id": string, "values": .object(["type": .string("array"), "items": pair])], required: ["skill_id", "values"])]
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        guard context.taskID == nil else { return [] }
        let live = WorkspaceSkillAccess.internalToolIDs(agentID: context.agentID, projection: try await repository.projection(identity: identity))
        return definitions.filter { live.contains($0.name) && context.allowedToolIDs.contains($0.name) }
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        guard context.taskID == nil, let agentID = context.agentID, context.allowedToolIDs.contains(call.name),
              case .object(let fields) = call.arguments,
              let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
              source.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.permissionDenied }
        let projection = try await repository.projection(identity: identity)
        let assigned = Set(WorkspaceSkillAccess.assignments(projection.grants).filter { $0.agentID == agentID && $0.assigned }.map(\.skillID))
        switch call.name {
        case "skill_list":
            let offset: Int
            if case .number(let value) = fields["offset"] {
                guard value.isFinite, value.rounded() == value, (0...100_000).contains(value) else { throw WorkspaceToolError.invalidArguments }
                offset = Int(value)
            } else { offset = 0 }
            let skills = projection.skills.filter { !$0.archived && assigned.contains($0.metadata.id) }.sorted { $0.metadata.id.uuidString < $1.metadata.id.uuidString }
            let page = try skills.dropFirst(offset).prefix(20).map { skill -> ChatJSON in
                guard let revision = projection.skillRevisions.first(where: { $0.metadata.id == skill.activeRevisionId }) else { throw WorkspaceSkillError.revisionUnavailable }
                return .object(["skill_id": .string(skill.metadata.id.uuidString), "name": .string(skill.name),
                    "instructions": .string(String(revision.instructions.prefix(500))),
                    "parameters": .array(try WorkspaceSkillService.parameters(revision).map { .object(["name": .string($0.name), "required": .bool($0.required)]) })])
            }
            return .object(["skills": .array(page), "has_more": .bool(offset + page.count < skills.count)])
        case "skill_run":
            guard case .string(let raw) = fields["skill_id"], let id = UUID(uuidString: raw), case .array(let pairs) = fields["values"] else { throw WorkspaceToolError.invalidArguments }
            var values: [String: String] = [:]
            for pair in pairs {
                guard case .object(let item) = pair, case .string(let name) = item["name"], case .string(let value) = item["value"], values[name] == nil else { throw WorkspaceToolError.invalidArguments }
                values[name] = value
            }
            do {
                let command = WorkspaceLogicalID.make(kind: "SkillToolRun", workspaceID: identity.workspaceID, parts: [source.metadata.id.uuidString, call.id])
                let taskID = try await WorkspaceSkillRunService(repository: repository, identity: identity).run(commandID: command,
                    skillID: id, agentID: agentID, values: values, conversationID: source.conversationId)
                return .object(["task_id": .string(taskID.uuidString), "state": .string("queued")])
            } catch let error as WorkspaceSkillError {
                return .object(["error": .string(String(describing: error))])
            } catch WorkspaceStorageError.invalidParameters {
                return .object(["error": .string("Provide exactly the declared parameters, including all required values.")])
            }
        default: throw WorkspaceToolError.unknownTool
        }
    }
    private func definition(_ name: String, _ description: String, properties: [String: ChatJSON], required: [String]) -> ChatToolDefinition {
        .init(name: name, description: description, parameters: .object(["type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(ChatJSON.string)), "additionalProperties": .bool(false)]))
    }
}
