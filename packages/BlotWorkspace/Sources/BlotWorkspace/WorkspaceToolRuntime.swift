import Foundation

public struct WorkspaceToolContext: Sendable {
    public let sourceMessageID: UUID
    public let taskID: UUID?
    public let agentID: UUID?
    public let connectionID: UUID?
    public let allowedToolIDs: Set<String>
    public init(sourceMessageID: UUID, taskID: UUID?, allowedToolIDs: Set<String>, agentID: UUID? = nil, connectionID: UUID? = nil) {
        self.sourceMessageID = sourceMessageID; self.taskID = taskID; self.allowedToolIDs = allowedToolIDs
        self.agentID = agentID; self.connectionID = connectionID
    }
}

public protocol WorkspaceToolExecuting: Sendable {
    var definitions: [ChatToolDefinition] { get }
    func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition]
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON
}

public extension WorkspaceToolExecuting {
    func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        definitions.filter { context.allowedToolIDs.contains($0.name) }
    }
}

public enum WorkspaceToolError: Error, Equatable, Sendable { case unknownTool, invalidArguments, approvalRequired, uncertainResult }

/// Validates complete calls against the declared schema before any tool implementation can run.
public struct WorkspaceToolRegistry: Sendable {
    private let providers: [any WorkspaceToolExecuting]
    public init(providers: [any WorkspaceToolExecuting]) throws {
        let names = providers.flatMap { $0.definitions.map(\.name) }
        guard Set(names).count == names.count else { throw WorkspaceToolError.invalidArguments }
        self.providers = providers
    }
    public func definitions(allowed: Set<String>) -> [ChatToolDefinition] { providers.flatMap(\.definitions).filter { allowed.contains($0.name) } }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        var result: [ChatToolDefinition] = []
        for provider in providers { result += try await provider.availableDefinitions(context: context) }
        return result
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        try _Concurrency.Task.checkCancellation()
        guard context.allowedToolIDs.contains(call.name),
              let provider = providers.first(where: { $0.definitions.contains { $0.name == call.name } }),
              let definition = provider.definitions.first(where: { $0.name == call.name }) else { throw WorkspaceToolError.unknownTool }
        try ToolArgumentValidator.validate(call.arguments, schema: definition.parameters)
        try _Concurrency.Task.checkCancellation()
        return try await provider.execute(call, context: context)
    }
}

private enum ToolArgumentValidator {
    static func validate(_ value: ChatJSON, schema: ChatJSON, depth: Int = 0) throws {
        guard depth <= 16, case .object(let spec) = schema, case .string(let type) = spec["type"] else { throw WorkspaceToolError.invalidArguments }
        if case .array(let choices) = spec["enum"], !choices.contains(value) { throw WorkspaceToolError.invalidArguments }
        switch (type, value) {
        case ("object", .object(let fields)):
            guard case .object(let properties) = spec["properties"] else { throw WorkspaceToolError.invalidArguments }
            if case .array(let required) = spec["required"] {
                for key in required { guard case .string(let name) = key, fields[name] != nil else { throw WorkspaceToolError.invalidArguments } }
            }
            guard Set(fields.keys).isSubset(of: Set(properties.keys)) else { throw WorkspaceToolError.invalidArguments }
            for (key, field) in fields { try validate(field, schema: properties[key]!, depth: depth + 1) }
        case ("string", .string(let text)): guard text.utf8.count <= 48 * 1024 else { throw WorkspaceToolError.invalidArguments }
        case ("integer", .number(let number)): guard number.isFinite, number.rounded() == number else { throw WorkspaceToolError.invalidArguments }
        case ("number", .number(let number)): guard number.isFinite else { throw WorkspaceToolError.invalidArguments }
        case ("boolean", .bool): break
        case ("array", .array(let items)):
            guard let schema = spec["items"], items.count <= 100 else { throw WorkspaceToolError.invalidArguments }
            for item in items { try validate(item, schema: schema, depth: depth + 1) }
        default: throw WorkspaceToolError.invalidArguments
        }
    }
}
