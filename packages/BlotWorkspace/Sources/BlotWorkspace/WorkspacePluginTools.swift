import BlotDomain
import Foundation

public struct WorkspacePluginDescriptor: Sendable, Equatable {
    public let id: String
    public let name: String
    public let summary: String
    public let available: Bool
    public init(id: String, name: String, summary: String, available: Bool) {
        self.id = id; self.name = name; self.summary = summary; self.available = available
    }
}

/// Platform adapters describe setup and verify access; discovery never grants it.
public protocol WorkspacePluginDirectory: Sendable {
    func plugins() async throws -> [WorkspacePluginDescriptor]
    func isConnected(pluginID: String, agentID: UUID) async throws -> Bool
}

public struct WorkspacePluginTools: WorkspaceToolExecuting {
    public static let toolIDs: Set<String> = ["plugin_catalog", "plugin_connect"]
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let directory: any WorkspacePluginDirectory
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, directory: any WorkspacePluginDirectory) {
        self.repository = repository; self.identity = identity; self.directory = directory
    }
    public var definitions: [ChatToolDefinition] {
        let string: ChatJSON = .object(["type": .string("string")])
        return [definition("plugin_catalog", "Find plugins and this agent's actual access on this device. Prefer query with the app name or ID. Lists connection metadata only, never private app content.", properties: ["query": string], required: []),
                definition("plugin_connect", "Offer the owner an inline connection card for a plugin from plugin_catalog. Opens that plugin's real setup flow and waits for connection or dismissal. The owner chooses resources and grants access; do not request credentials in chat. After connection, discover newly available tools and continue the original task.",
                    properties: ["plugin_id": string, "reason": string], required: ["plugin_id", "reason"])]
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        guard context.agentID != nil else { return [] }
        return definitions.filter { context.allowedToolIDs.contains($0.name) && ($0.name != "plugin_connect" || context.taskID == nil) }
    }
    public func preferredInitialTool(userRequest: String, context: WorkspaceToolContext) async throws -> String? {
        let policy = WorkspaceCapabilityPolicy(userRequest: userRequest)
        if policy.queriesConnections { return "plugin_catalog" }
        guard context.taskID == nil, let agentID = context.agentID, policy.requestsAction else { return nil }
        for plugin in try await directory.plugins() where plugin.available && policy.mentions(id: plugin.id, name: plugin.name) {
            if try await !directory.isConnected(pluginID: plugin.id, agentID: agentID) { return "plugin_catalog" }
        }
        return nil
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        guard context.allowedToolIDs.contains(call.name), let agentID = context.agentID,
              let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
              source.metadata.ownerId == identity.ownerID,
              let chat = try await repository.record(BlotV3.Conversation.self, id: source.conversationId, workspaceID: identity.workspaceID), !chat.archived else { throw WorkspaceStorageError.permissionDenied }
        let projection = try await repository.projection(identity: identity)
        guard projection.agents.contains(where: { $0.metadata.id == agentID }), chat.agentId == agentID || chat.kind == .group && projection.participants.contains(where: {
            $0.conversationId == chat.metadata.id && $0.participantId == agentID && $0.kind == .agent && !$0.removed
        }) else { throw WorkspaceStorageError.permissionDenied }
        let catalog = try await directory.plugins()
        switch call.name {
        case "plugin_catalog":
            let query: String
            if case .object(let fields) = call.arguments, case .string(let text) = fields["query"] { query = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            else { query = "" }
            var entries: [ChatJSON] = []
            for plugin in catalog where query.isEmpty || plugin.id.localizedCaseInsensitiveContains(query) || plugin.name.localizedCaseInsensitiveContains(query) {
                entries.append(.object(["plugin_id": .string(plugin.id), "name": .string(plugin.name), "summary": .string(plugin.summary),
                    "can_connect": .bool(plugin.available), "connected_for_agent": .bool(try await directory.isConnected(pluginID: plugin.id, agentID: agentID))]))
            }
            return .object(["plugins": .array(entries), "query": .string(query)])
        case "plugin_connect":
            guard context.taskID == nil else { throw WorkspaceStorageError.permissionDenied }
            guard case .object(let fields) = call.arguments, case .string(let pluginID) = fields["plugin_id"],
                  case .string(let reason) = fields["reason"], !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let plugin = catalog.first(where: { $0.id == pluginID }) else { throw WorkspaceToolError.invalidArguments }
            guard plugin.available else { return .object(["state": .string("unavailable"), "plugin_id": .string(pluginID)]) }
            if try await directory.isConnected(pluginID: pluginID, agentID: agentID) {
                return .object(["state": .string("connected"), "plugin_id": .string(pluginID)])
            }
            let id = WorkspaceToolCallIdentity.actionID(workspaceID: identity.workspaceID, sourceID: context.sourceMessageID, callID: call.id)
            let service = WorkspaceConversationCardService(repository: repository, identity: identity)
            try await service.create(id: id, sourceMessageID: source.metadata.id, operationID: id, agentID: agentID,
                content: .connectionRequest(.init(pluginID: pluginID, name: plugin.name, reason: reason, agentID: agentID)))
            let response = try await service.waitForResponse(cardID: id)
            let connected: Bool
            if response.action == "connected" { connected = try await directory.isConnected(pluginID: pluginID, agentID: agentID) }
            else { connected = false }
            return .object(["state": .string(connected ? "connected" : response.action == "dismiss" ? "dismissed" : "not_connected"),
                "plugin_id": .string(pluginID), "access_granted": .bool(connected)])
        default: throw WorkspaceToolError.unknownTool
        }
    }
    private func definition(_ name: String, _ description: String, properties: [String: ChatJSON], required: [String]) -> ChatToolDefinition {
        .init(name: name, description: description, parameters: .object(["type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(ChatJSON.string)), "additionalProperties": .bool(false)]))
    }
}
