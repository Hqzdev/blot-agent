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
        let parameter: ChatJSON = .object(["type": .string("object"), "properties": .object(["name": string, "required": .object(["type": .string("boolean")])]),
            "required": .array([.string("name"), .string("required")]), "additionalProperties": .bool(false)])
        return [definition("skill_list", "List your saved skills and the built-in Skill Creator. Use offset for further pages. Read a skill before reusing it.",
                    properties: ["offset": .object(["type": .string("integer")])], required: []),
                definition("skill_read", "Read an assigned skill's complete instructions, parameters and tool requirements. Use skill_id=skill-creator for the built-in creation guide.",
                    properties: ["skill_id": string], required: ["skill_id"]),
                definition("skill_create", "Skill Creator: save a reusable skill and assign it to yourself. First check skill_list to avoid duplicates. Use {{parameter}} tokens with declared names; never put passwords or tokens in instructions. Use tool_ids=[] for text-only skills such as summarization. Include only real assigned external tools needed when the skill runs, never skill_create or invented capabilities. Saving does not execute the skill or grant tool access.",
                    properties: ["name": string, "instructions": string, "parameters": .object(["type": .string("array"), "items": parameter]),
                                 "tool_ids": .object(["type": .string("array"), "items": string])], required: ["name", "instructions", "parameters", "tool_ids"]),
                definition("skill_run", "Queue an assigned skill as a task. This does not mean execution has completed.",
                    properties: ["skill_id": string, "values": .object(["type": .string("array"), "items": pair])], required: ["skill_id", "values"])]
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        guard context.taskID == nil else { return [] }
        let live = WorkspaceSkillAccess.internalToolIDs(agentID: context.agentID, projection: try await repository.projection(identity: identity))
        return definitions.filter { live.contains($0.name) && context.allowedToolIDs.contains($0.name) }
    }
    public func preferredInitialTool(userRequest: String, context: WorkspaceToolContext) async throws -> String? {
        let policy = WorkspaceCapabilityPolicy(userRequest: userRequest)
        return context.taskID == nil && (policy.createsSkill || policy.usesSkill || policy.queriesSkills) ? "skill_list" : nil
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        guard context.taskID == nil, let agentID = context.agentID, context.allowedToolIDs.contains(call.name),
              case .object(let fields) = call.arguments,
              let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
              source.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.permissionDenied }
        let projection = try await repository.projection(identity: identity)
        guard let chat = projection.conversations.first(where: { $0.metadata.id == source.conversationId && !$0.archived }),
              chat.agentId == agentID || chat.kind == .group && projection.participants.contains(where: {
                  $0.conversationId == chat.metadata.id && $0.kind == .agent && $0.participantId == agentID && !$0.removed
              }) else { throw WorkspaceStorageError.permissionDenied }
        let assigned = Set(WorkspaceSkillAccess.assignments(projection.grants).filter { $0.agentID == agentID && $0.assigned }.map(\.skillID))
        switch call.name {
        case "skill_create":
            guard WorkspaceToolRestrictions(userRequest: source.content).allows(operation: "create"),
                  case .string(let name) = fields["name"], case .string(let instructions) = fields["instructions"],
                  case .array(let rawParameters) = fields["parameters"], case .array(let rawTools) = fields["tool_ids"],
                  let configuration = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection) else { throw WorkspaceStorageError.permissionDenied }
            let parameters = try rawParameters.map { value -> SkillParameter in
                guard case .object(let item) = value, case .string(let name) = item["name"], case .bool(let required) = item["required"] else { throw WorkspaceToolError.invalidArguments }
                return .init(name: name, required: required)
            }
            let tools = try rawTools.map { value -> String in
                guard case .string(let name) = value else { throw WorkspaceToolError.invalidArguments }; return name
            }
            guard Set(tools).isSubset(of: Set(configuration.toolIds)) else {
                return .object(["error": .string("tools_unavailable"), "instructions": .string("No skill was saved. For text-only work use tool_ids=[]. Otherwise choose only actual assigned tools, or connect the required plugin first."),
                    "allowed_tool_ids": .array(configuration.toolIds.map(ChatJSON.string))])
            }
            let id = WorkspaceLogicalID.make(kind: "SkillToolCreate", workspaceID: identity.workspaceID, parts: [source.metadata.id.uuidString, call.id])
            do {
                _ = try await WorkspaceSkillService(repository: repository, identity: identity).save(commandID: id, name: name,
                    instructions: instructions, parameters: parameters, toolIDs: tools)
            } catch WorkspaceSkillError.invalidTemplate {
                return .object(["error": .string("invalid_template"), "instructions": .string("No skill was saved. Use only {{parameter}} tokens whose names are declared in parameters. Correct the template and try again with a new call ID.")])
            } catch WorkspaceStorageError.invalidParameters {
                return .object(["error": .string("invalid_parameters"), "instructions": .string("No skill was saved. Provide a nonempty name and instructions, unique parameters with ASCII names, and unique assigned tool IDs.")])
            }
            let assignment = WorkspaceLogicalID.make(kind: "SkillToolAssign", workspaceID: identity.workspaceID, parts: [id.uuidString, agentID.uuidString])
            try await WorkspaceSkillAssignmentService(repository: repository, identity: identity).set(commandID: assignment,
                skillID: id, agentID: agentID, assigned: true, expectedVersion: 0)
            try WorkspaceSkillAccess.require(skillID: id, agentID: agentID, projection: try await repository.projection(identity: identity))
            return .object(["skill_id": .string(id.uuidString), "name": .string(name), "state": .string("saved"), "assigned_to": .string(agentID.uuidString)])
        case "skill_read":
            guard case .string(let raw) = fields["skill_id"] else { throw WorkspaceToolError.invalidArguments }
            if raw == "skill-creator" { return Self.creator }
            guard let id = UUID(uuidString: raw) else { throw WorkspaceToolError.invalidArguments }
            try WorkspaceSkillAccess.require(skillID: id, agentID: agentID, projection: projection)
            guard let skill = projection.skills.first(where: { $0.metadata.id == id }),
                  let revision = projection.skillRevisions.first(where: { $0.metadata.id == skill.activeRevisionId }) else { throw WorkspaceSkillError.revisionUnavailable }
            return .object(["skill_id": .string(id.uuidString), "name": .string(skill.name), "revision_id": .string(revision.metadata.id.uuidString),
                "instructions": .string(revision.instructions), "tool_ids": .array(revision.toolIds.map(ChatJSON.string)),
                "parameters": .array(try WorkspaceSkillService.parameters(revision).map { .object(["name": .string($0.name), "required": .bool($0.required)]) })])
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
            return .object(["skills": .array(page), "built_in": .array(offset == 0 ? [Self.creator] : []), "has_more": .bool(offset + page.count < skills.count)])
        case "skill_run":
            guard !WorkspaceCapabilityPolicy(userRequest: source.content).forbidsSkillRun else { throw WorkspaceStorageError.permissionDenied }
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
    private static var creator: ChatJSON {
        .object(["skill_id": .string("skill-creator"), "name": .string("Skill Creator"), "built_in": .bool(true),
            "instructions": .string("Identify a reusable task, check skill_list, define concise instructions and required parameters, and call skill_create. Declare {{parameter}} tokens. Include only tools already assigned to this agent; connect missing plugins first. Save reusable instructions, not transient results or secrets. Read the saved skill with skill_read and use skill_run with explicit values when execution is requested. Never claim a queued run is complete."),
            "creation_tool": .string("skill_create")])
    }
    private func definition(_ name: String, _ description: String, properties: [String: ChatJSON], required: [String]) -> ChatToolDefinition {
        .init(name: name, description: description, parameters: .object(["type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(ChatJSON.string)), "additionalProperties": .bool(false)]))
    }
}
