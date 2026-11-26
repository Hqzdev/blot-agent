import BlotDomain
import Foundation

public struct WorkspaceToolContext: Sendable {
    public let inlineCards: Bool
    public let sourceMessageID: UUID
    public let taskID: UUID?
    public let agentID: UUID?
    public let connectionID: UUID?
    public let allowedToolIDs: Set<String>
    public init(sourceMessageID: UUID, taskID: UUID?, allowedToolIDs: Set<String>, agentID: UUID? = nil, connectionID: UUID? = nil, inlineCards: Bool = false) {
        self.inlineCards = inlineCards
        self.sourceMessageID = sourceMessageID; self.taskID = taskID; self.allowedToolIDs = allowedToolIDs
        self.agentID = agentID; self.connectionID = connectionID
    }
}

public protocol WorkspaceToolExecuting: Sendable {
    var definitions: [ChatToolDefinition] { get }
    func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition]
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON
    func validate(_ call: ChatToolCall, definition: ChatToolDefinition) throws
    func preferredInitialTool(userRequest: String, context: WorkspaceToolContext) async throws -> String?
    func invalidArgumentsResult(for call: ChatToolCall) -> ChatJSON?
}

public extension WorkspaceToolExecuting {
    func preferredInitialTool(userRequest: String, context: WorkspaceToolContext) async throws -> String? { nil }
    func invalidArgumentsResult(for call: ChatToolCall) -> ChatJSON? { nil }
    func validate(_ call: ChatToolCall, definition: ChatToolDefinition) throws {
        try ToolArgumentValidator.validate(call.arguments, schema: definition.parameters)
    }
    func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        definitions.filter { context.allowedToolIDs.contains($0.name) }
    }
}

public enum WorkspaceToolError: Error, Equatable, Sendable { case unknownTool, invalidArguments, approvalRequired, uncertainResult }

/// Validates complete calls against the declared schema before any tool implementation can run.
public struct WorkspaceToolRegistry: Sendable {
    private let providers: [any WorkspaceToolExecuting]
    private let inlineCards: Bool
    private let restrictedToolIDs: Set<String>?
    private let beforeExecute: (@Sendable (ChatToolCall, WorkspaceToolContext) async throws -> Void)?
    public init(providers: [any WorkspaceToolExecuting], inlineCards: Bool = false, restrictedToolIDs: Set<String>? = nil,
                beforeExecute: (@Sendable (ChatToolCall, WorkspaceToolContext) async throws -> Void)? = nil) throws {
        let names = providers.flatMap { $0.definitions.map(\.name) }
        guard Set(names).count == names.count else { throw WorkspaceToolError.invalidArguments }
        self.providers = providers; self.inlineCards = inlineCards; self.restrictedToolIDs = restrictedToolIDs; self.beforeExecute = beforeExecute
    }
    public func assignedToolIDs(configuration: BlotV3.AgentConfigurationRevision?, projection: WorkspaceProjection, deviceID: UUID) -> Set<String> {
        guard let configuration else { return [] }
        var assigned = Set(configuration.toolIds)
        let connections = projection.connections.filter { WorkspacePluginAccess.isActive($0, deviceID: deviceID, projection: projection) }
        let applePrefixes = connections.compactMap { connection in
            WorkspacePluginAccess.hasAppleGrant(connection, grants: projection.grants)
                ? WorkspacePluginAccess.appleToolPrefix(connection.pluginId) : nil
        }
        for connection in connections { assigned.formUnion(WorkspacePluginAccess.externalTools(connection.pluginId)) }
        for record in projection.mcpConnections where WorkspacePluginAccess.isActive(record, deviceID: deviceID, projection: projection) {
            assigned.formUnion(record.toolIds)
        }
        if !applePrefixes.isEmpty {
            assigned.formUnion(providers.flatMap(\.definitions).map(\.name).filter { name in
                applePrefixes.contains { name.hasPrefix($0) }
            })
        }
        return assigned
    }
    public var inlineCardsEnabled: Bool { inlineCards }
    public func preferredInitialTool(userRequest: String, context: WorkspaceToolContext, available: Set<String>) async throws -> String? {
        for provider in providers {
            if let name = try await provider.preferredInitialTool(userRequest: userRequest, context: context), available.contains(name) { return name }
        }
        return nil
    }
    public func definitions(allowed: Set<String>) -> [ChatToolDefinition] { providers.flatMap(\.definitions).filter { allowed.contains($0.name) && (restrictedToolIDs?.contains($0.name) ?? true) } }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        var result: [ChatToolDefinition] = []
        for provider in providers { result += try await provider.availableDefinitions(context: context) }
        return result.filter { restrictedToolIDs?.contains($0.name) ?? true }
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        try _Concurrency.Task.checkCancellation()
        guard context.allowedToolIDs.contains(call.name),
              restrictedToolIDs?.contains(call.name) ?? true,
              let provider = providers.first(where: { $0.definitions.contains { $0.name == call.name } }),
              let definition = provider.definitions.first(where: { $0.name == call.name }) else { throw WorkspaceToolError.unknownTool }
        do { try provider.validate(call, definition: definition) }
        catch WorkspaceToolError.invalidArguments {
            if let result = provider.invalidArgumentsResult(for: call) { return result }
            throw WorkspaceToolError.invalidArguments
        }
        try await beforeExecute?(call, context)
        try _Concurrency.Task.checkCancellation()
        let executionContext = WorkspaceToolContext(sourceMessageID: context.sourceMessageID, taskID: context.taskID, allowedToolIDs: context.allowedToolIDs, agentID: context.agentID, connectionID: context.connectionID, inlineCards: inlineCards)
        return try await provider.execute(call, context: executionContext)
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
