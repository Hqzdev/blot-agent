import BlotDomain
import Foundation

public struct MCPInspection: Sendable {
    public let id: UUID
    public let name: String
    public let tools: [MCPTool]
    let configurationID: UUID
    let configuration: MCPConfiguration
}

public struct MCPAccess: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let tools: [MCPTool]
    public let selectedTools: Set<String>
    public let agentIDs: Set<UUID>
    public let enabled: Bool
}

struct MCPLocalConnection: Codable, Sendable {
    let id: UUID
    let name: String
    let configurationID: UUID
    let configuration: MCPConfiguration
    let tools: [MCPTool]
    var selectedTools: Set<String>
    var agentIDs: Set<UUID>
    var enabled: Bool
    var toolIDs: [String] { tools.filter { selectedTools.contains($0.name) }.map { $0.toolID(connectionID: id, configurationID: configurationID) } }
}

/// Authority and secrets are device-only. Replicated McpConnection rows cannot start a process or grant access.
public actor WorkspaceMCPService {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let credentials: any WorkspaceCredentialStore
    private let connect: @Sendable (MCPConfiguration) throws -> MCPClient
    private var connections: [MCPLocalConnection]?
    private var mutating = false
    private var suspended = false
    private var clients: [UUID: (UUID, MCPClient)] = [:]
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore,
                connect: @escaping @Sendable (MCPConfiguration) throws -> MCPClient = { try MCPClient.connect(configuration: $0) }) {
        self.repository = repository; self.identity = identity; self.credentials = credentials; self.connect = connect
    }
    private var key: String { "mcp:" + identity.ownerID.uuidString + ":" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    private func load() async throws -> [MCPLocalConnection] {
        if let connections { return connections }
        let data = try await credentials.read(key)
        let loaded = try data.map { try WorkspaceCoding.decode([MCPLocalConnection].self, from: $0) } ?? []
        if connections == nil { connections = loaded }
        return connections ?? []
    }
    private func persist(_ values: [MCPLocalConnection]) async throws {
        // Fail closed even if the credential store becomes unavailable.
        connections = values
        try await credentials.write(WorkspaceCoding.encode(values), name: key)
    }
    public func inspect(name: String, configuration: MCPConfiguration) async throws -> MCPInspection {
        guard !suspended else { throw MCPError.unavailable }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 200 else { throw MCPError.configuration }
        try configuration.validate()
        let id = UUID(), client = try connect(configuration)
        clients[id] = (id, client)
        do {
            let tools = try await client.tools(); await client.close(); clients[id] = nil
            guard !suspended else { throw MCPError.unavailable }
            try Self.checkCatalog(tools, configuration: configuration)
            return MCPInspection(id: id, name: name, tools: tools, configurationID: UUID(), configuration: configuration)
        } catch { await client.close(); clients[id] = nil; throw error }
    }
    public func access() async throws -> [MCPAccess] {
        try await load().map { .init(id: $0.id, name: $0.name, tools: $0.tools, selectedTools: $0.selectedTools, agentIDs: $0.agentIDs, enabled: $0.enabled) }
    }
    @discardableResult
    public func save(_ inspection: MCPInspection, selectedTools: Set<String>, agentIDs: Set<UUID>) async throws -> UUID {
        try await saveConnection(.init(id: inspection.id, name: inspection.name, configurationID: inspection.configurationID,
            configuration: inspection.configuration, tools: inspection.tools, selectedTools: selectedTools, agentIDs: agentIDs, enabled: false))
        return inspection.id
    }
    public func setAccess(id: UUID, selectedTools: Set<String>, agentIDs: Set<UUID>) async throws {
        guard var entry = try await load().first(where: { $0.id == id }) else { throw MCPError.unavailable }
        entry.selectedTools = selectedTools; entry.agentIDs = agentIDs
        try await saveConnection(entry)
    }
    private func saveConnection(_ entry: MCPLocalConnection) async throws {
        guard !mutating, !suspended else { throw MCPError.accessChanged }; mutating = true; defer { mutating = false }
        guard !entry.selectedTools.isEmpty, !entry.agentIDs.isEmpty,
              entry.selectedTools.isSubset(of: Set(entry.tools.map(\.name))) else { throw MCPError.configuration }
        var values = try await load()
        guard values.count < 30 || values.contains(where: { $0.id == entry.id }) else { throw MCPError.configuration }
        let previous = values.first { $0.id == entry.id }
        var disabled = entry; disabled.enabled = false
        values.removeAll { $0.id == entry.id }; values.append(disabled)
        try await persist(values)
        await closeClients(connectionID: entry.id)
        guard !suspended else { throw MCPError.unavailable }
        struct Input: Encodable { let id: UUID; let tools: [String]; let agents: [UUID] }
        let commandID = UUID()
        let command = try WorkspaceCommand(type: "mcp.save", workspaceID: identity.workspaceID,
            payload: Input(id: entry.id, tools: entry.toolIDs.sorted(), agents: entry.agentIDs.sorted { $0.uuidString < $1.uuidString })).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            try tx.requireResolved(kind: "McpConnection", id: entry.id)
            let old = try tx.record(BlotV3.McpConnection.self, id: entry.id)
            let record = try BlotV3.McpConnection(metadata: tx.metadata(id: entry.id, now: Date(), replacing: old?.metadata), name: entry.name,
                transport: entry.configuration.transport == .http ? "STREAMABLE_HTTP" : "STDIO",
                endpoint: "device:" + tx.identity.deviceID.uuidString, toolIds: entry.toolIDs.sorted(), state: .connected)
            for agentID in entry.agentIDs.union(previous?.agentIDs ?? []) {
                try Self.updateAgent(tx, id: agentID, removing: Set((previous?.toolIDs ?? []) + (old?.toolIds ?? [])), adding: entry.agentIDs.contains(agentID) ? entry.toolIDs : [])
            }
            try tx.put(record, expectedVersion: old?.metadata.version ?? 0)
            return entry.id
        }
        guard !suspended else { throw MCPError.unavailable }
        disabled.enabled = true
        values.removeAll { $0.id == entry.id }; values.append(disabled)
        do { try await persist(values) }
        catch { connections = values.map { var value = $0; if value.id == entry.id { value.enabled = false }; return value }; throw error }
    }
    public func refresh(id: UUID) async throws {
        guard !mutating, !suspended, var entry = try await load().first(where: { $0.id == id }) else { throw MCPError.accessChanged }
        mutating = true; defer { mutating = false }
        // Refresh revokes all access before making a network request. The owner must select it again.
        entry.enabled = false
        var values = try await load(); values.removeAll { $0.id == id }; values.append(entry); try await persist(values)
        await closeClients(connectionID: id)
        let client = try connect(entry.configuration); let sessionID = UUID(); clients[sessionID] = (id, client)
        do {
            let tools = try await client.tools(); await client.close(); clients[sessionID] = nil
            guard !suspended else { throw MCPError.unavailable }
            try Self.checkCatalog(tools, configuration: entry.configuration)
            let fresh = MCPLocalConnection(id: id, name: entry.name, configurationID: UUID(), configuration: entry.configuration,
                tools: tools, selectedTools: [], agentIDs: entry.agentIDs, enabled: false)
            values.removeAll { $0.id == id }; values.append(fresh); try await persist(values)
        } catch { await client.close(); clients[sessionID] = nil; throw error }
    }
    public func disconnect(id: UUID) async throws {
        guard !mutating else { throw MCPError.accessChanged }; mutating = true; defer { mutating = false }
        var values = try await load()
        guard let entry = values.first(where: { $0.id == id }) else { throw MCPError.unavailable }
        values.removeAll { $0.id == id }; try await persist(values)
        await closeClients(connectionID: id)
        struct Input: Encodable { let id: UUID }
        let command = try WorkspaceCommand(type: "mcp.disconnect", workspaceID: identity.workspaceID, payload: Input(id: id)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            for agentID in entry.agentIDs { try Self.updateAgent(tx, id: agentID, removing: Set(entry.toolIDs), adding: []) }
            if let old = try tx.record(BlotV3.McpConnection.self, id: id) { try tx.delete(old) }
            return id
        }
    }
    public func provider(confirm: @escaping @Sendable (String, String) async throws -> Bool) async throws -> MCPToolProvider {
        let records = try await repository.records(BlotV3.McpConnection.self, workspaceID: identity.workspaceID)
        let entries = records.isEmpty ? [] : try await load().filter(\.enabled)
        return MCPToolProvider(repository: repository, identity: identity, service: self, connections: entries, confirm: confirm)
    }
    func authorize(_ entry: MCPLocalConnection, tool: MCPTool, context: WorkspaceToolContext) async throws {
        guard !suspended, !mutating, let current = try await load().first(where: { $0.id == entry.id }), current.enabled,
              current.configurationID == entry.configurationID, current.tools.contains(tool), current.selectedTools.contains(tool.name),
              let agentID = context.agentID, current.agentIDs.contains(agentID) else { throw MCPError.accessChanged }
        let name = tool.toolID(connectionID: entry.id, configurationID: entry.configurationID)
        let projection = try await repository.projection(identity: identity)
        guard let source = projection.messages.first(where: { $0.metadata.id == context.sourceMessageID }), source.metadata.ownerId == identity.ownerID,
              WorkspaceToolRestrictions(userRequest: source.content).allows(operation: "send"),
              WorkspaceToolRestrictions(userRequest: source.content).allows(operation: "update"),
              context.allowedToolIDs.contains(name),
              try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection)?.toolIds.contains(name) == true,
              let record = try await repository.record(BlotV3.McpConnection.self, id: entry.id, workspaceID: identity.workspaceID),
              record.state == .connected, record.endpoint == "device:" + identity.deviceID.uuidString, record.toolIds.contains(name),
              !projection.conflicts.contains(where: { !$0.resolved && ($0.recordId == entry.id || $0.recordId == agentID) }) else { throw MCPError.accessChanged }
        if let taskID = context.taskID {
            guard let task = projection.tasks.first(where: { $0.metadata.id == taskID }), task.execution.executorDeviceId == identity.deviceID,
                  !WorkspaceTaskService.terminal(task.state), task.state != .paused else { throw MCPError.accessChanged }
        }
    }
    func open(_ entry: MCPLocalConnection) throws -> (UUID, MCPClient) {
        guard !suspended, !mutating, connections?.contains(where: { $0.id == entry.id && $0.enabled && $0.configurationID == entry.configurationID }) == true else { throw MCPError.accessChanged }
        let id = UUID(), client = try connect(entry.configuration); clients[id] = (entry.id, client); return (id, client)
    }
    public func resolve(invocationID: UUID, succeeded: Bool) async throws {
        let projection = try await repository.projection(identity: identity)
        guard let invocation = projection.invocations.first(where: { $0.metadata.id == invocationID && $0.state == .unknown && $0.execution.executorDeviceId == identity.deviceID }),
              let action = projection.actions.first(where: { $0.metadata.id == invocation.preparedActionId && $0.toolId.hasPrefix("mcp_") }),
              try await load().contains(where: { $0.id.uuidString == action.resource }) else { throw MCPError.accessChanged }
        let result = ChatJSON.object(["state": .string(succeeded ? "succeeded" : "failed"), "owner_verified": .bool(true)])
        try await WorkspacePermissionService(repository: repository, identity: identity).finish(commandID: UUID(), invocationID: invocationID,
            state: succeeded ? .succeeded : .failed, result: String(decoding: try WorkspaceCoding.encode(result), as: UTF8.self))
    }
    func close(_ id: UUID) async { guard let (_, client) = clients.removeValue(forKey: id) else { return }; await client.close() }
    private func closeClients(connectionID: UUID) async {
        for id in clients.filter({ $0.value.0 == connectionID }).map(\.key) { await close(id) }
    }
    public func stop() async { suspended = true; for id in Array(clients.keys) { await close(id) } }
    public func resume() { suspended = false }
    private static func checkCatalog(_ tools: [MCPTool], configuration: MCPConfiguration) throws {
        let data = try WorkspaceCoding.encode(tools)
        let json = try JSONDecoder().decode(ChatJSON.self, from: data)
        guard !json.mcpContains(configuration.secrets) else { throw MCPError.protocolViolation }
    }
    private static func updateAgent(_ tx: WorkspaceTransaction, id: UUID, removing: Set<String>, adding: [String]) throws {
        guard let agent = try tx.record(BlotV3.AgentProfile.self, id: id) else {
            if adding.isEmpty { return }; throw WorkspaceStorageError.missingRecord
        }
        try tx.requireResolved(kind: "AgentProfile", id: id)
        guard let configurationID = agent.configurationId else { throw WorkspaceStorageError.invalidRecord }
        let configuration = try tx.require(BlotV3.AgentConfigurationRevision.self, id: configurationID)
        let tools = Set(configuration.toolIds).subtracting(removing).union(adding).sorted()
        guard tools.count <= 100 else { throw WorkspaceStorageError.invalidParameters }
        let revisionID = UUID()
        try tx.put(BlotV3.AgentConfigurationRevision(metadata: tx.metadata(id: revisionID, now: Date()), agentId: id,
            revision: agent.metadata.version + 1, instructions: configuration.instructions, toolIds: tools, modelId: configuration.modelId), expectedVersion: 0)
        try tx.put(BlotV3.AgentProfile(metadata: tx.metadata(id: id, now: Date(), replacing: agent.metadata), name: agent.name, roleId: agent.roleId,
            avatarShape: agent.avatarShape, avatarColor: agent.avatarColor, instructions: agent.instructions, modelId: agent.modelId,
            accessMode: agent.accessMode, configurationId: revisionID), expectedVersion: agent.metadata.version)
    }
}
