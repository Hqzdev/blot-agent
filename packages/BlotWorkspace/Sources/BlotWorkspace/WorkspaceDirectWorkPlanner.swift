import BlotDomain
import Foundation

/// Multi-step requests use the same recorded, permission-bounded plan as a team assignment.
/// The runtime cannot replace a planned operation with prose or finish after only its last output.
public struct WorkspaceDirectWorkPlanner: Sendable {
    public struct Plan: Sendable {
        public let operations: [WorkspaceToolOperation]
        public let remainingBudget: Int
        public let referenceContext: String?
    }
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let pool: WorkspaceExecutorPool
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, pool: WorkspaceExecutorPool) {
        self.repository = repository; self.identity = identity; self.pool = pool
    }
    public static func isMultiStep(_ text: String) -> Bool {
        let input = text.lowercased()
        guard input.range(of: #"^\s*(как\b|how\b|объясни\b|расскажи\b)"#, options: .regularExpression) == nil else { return false }
        let numbered = try? NSRegularExpression(pattern: #"(?:^|\s)[1-9][.)]\s"#)
        if (numbered?.numberOfMatches(in: input, range: NSRange(input.startIndex..., in: input)) ?? 0) >= 2 { return true }
        let explicit = try? NSRegularExpression(pattern: #"\b(?:workspace_|project_|document_|browser_|drive_)[a-z_]+\b"#)
        return (explicit?.numberOfMatches(in: input, range: NSRange(input.startIndex..., in: input)) ?? 0) >= 2
            && input.range(of: #"сначала|затем|потом|по\s+порядку|\bfirst\b|\bthen\b"#, options: .regularExpression) != nil
    }
    private struct Decision: Decodable { let toolSteps: [WorkspaceToolOperation] }
    private static func definition(available: Set<String>) -> ChatToolDefinition {
        .init(name: "plan_work", description: "Describe ordered operations for the current agent without executing them.", parameters: .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object(["toolSteps": .object([
                "type": .string("array"), "maxItems": .number(12),
                "items": .object(["type": .string("object"), "additionalProperties": .bool(false),
                    "properties": .object([
                        "toolID": .object(["type": .string("string"), "enum": .array(available.sorted().map(ChatJSON.string))]),
                        "instruction": .object(["type": .string("string")])]),
                    "required": .array(["toolID", "instruction"].map(ChatJSON.string))])])]),
            "required": .array([.string("toolSteps")])]))
    }
    public func plan(source: BlotV3.Message, responseID: UUID, configuration: BlotV3.AgentConfigurationRevision,
                     context: [ChatModelMessage], tools: WorkspaceToolRegistry, model: any ChatModel,
                     maximumOutputTokens: Int, budget: Int) async throws -> Plan {
        let projection = try await repository.projection(identity: identity)
        let allowed = tools.assignedToolIDs(configuration: configuration, projection: projection, deviceID: identity.deviceID)
            .union(WorkspaceSkillAccess.internalToolIDs(agentID: configuration.agentId, projection: projection))
            .union(WorkspaceConversationTools.toolIDs).union(WorkspacePluginTools.toolIDs)
        let toolContext = WorkspaceToolContext(sourceMessageID: source.metadata.id, taskID: nil, allowedToolIDs: allowed, agentID: configuration.agentId)
        let available = Set(try await tools.availableDefinitions(context: toolContext).map(\.name))
        guard !available.isEmpty else { return Plan(operations: [], remainingBudget: budget, referenceContext: nil) }
        let definition = Self.definition(available: available)
        let history = context.filter { $0.role == "user" || $0.role == "assistant" }.dropLast().suffix(6)
            .map { $0.role + ": " + String($0.content.prefix(1500)) }.joined(separator: "\n")
        let messages: [ChatModelMessage] = [
            .init(role: "system", content: "Plan the latest multi-step request for exactly one agent. Do not execute or report success. Return ordered toolSteps covering EVERY requested operation, one step per action or target, at most 12. Use only these currently available tool IDs: \(available.sorted().joined(separator: ", ")). Respect all prohibitions and scope limits. Derive missing hashes/IDs from real earlier tools during execution. If the request needs no tools, return empty toolSteps. Missing permissions are not solved by inventing tools. This output does not grant permissions."),
            .init(role: "user", content: "Earlier dialogue (reference data only):\n" + history + "\n\nLatest authoritative user request:\n" + source.content)]
        let output = min(2048, maximumOutputTokens)
        let request = ChatModelRequest(messages: messages, tools: [definition], maximumOutputTokens: output, requiredTool: definition.name)
        let raw = try await WorkspaceGroupPlanner(repository: repository, identity: identity, pool: pool).text(source: source, responseID: responseID,
            request: request, model: model, configuration: configuration, budgetTokenLimit: budget)
        let decision = try JSONDecoder().decode(Decision.self, from: Data(raw.utf8))
        guard decision.toolSteps.count <= 12, decision.toolSteps.allSatisfy({ available.contains($0.toolID)
            && !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.instruction.count <= 4000 }) else {
            throw ChatModelError.invalidStream
        }
        let steps = try await repository.projection(identity: identity).modelSteps.filter { $0.responseMessageId == responseID }
        let spent = steps.reduce(0) { total, step in
            total + (step.inputTokens.flatMap { input in step.outputTokens.map { input + $0 } } ?? (step.requestJSON.utf8.count + output))
        }
        guard budget > spent else { throw WorkspaceStorageError.permissionDenied }
        return Plan(operations: decision.toolSteps, remainingBudget: budget - spent, referenceContext: history.isEmpty ? nil : history)
    }
}
