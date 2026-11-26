import BlotDomain
import Foundation

/// Replicated access describes plugin connections; device-local credentials remain necessary for execution.
public struct WorkspaceExternalAccess: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }
    public func save(id: UUID, plugin: String, service: String, account: String, scopes: [String]) async throws {
        try _Concurrency.Task.checkCancellation()
        guard !account.isEmpty else { throw WorkspaceStorageError.invalidParameters }
        struct Input: Encodable { let id: UUID; let plugin: String; let account: String; let scopes: [String] }
        let command = try WorkspaceCommand(type: "external.connect", workspaceID: identity.workspaceID,
            payload: Input(id: id, plugin: plugin, account: account, scopes: scopes)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            try _Concurrency.Task.checkCancellation()
            let old = try tx.record(BlotV3.Connection.self, id: id)
            if let old { guard old.deviceId == identity.deviceID, old.pluginId == plugin else { throw WorkspaceStorageError.permissionDenied } }
            try tx.requireResolved(kind: "Connection", id: id)
            try tx.put(BlotV3.Connection(metadata: tx.metadata(id: id, now: Date(), replacing: old?.metadata), service: service, accountName: account,
                scopes: scopes, state: .connected, deviceId: identity.deviceID, pluginId: plugin, resourceIds: [account],
                allowedOperations: ["read", "create", "update", "send"]), expectedVersion: old?.metadata.version ?? 0)
            return id
        }
    }
    public func authorize(id: UUID, tool: String, operation: String, context: WorkspaceToolContext) async throws {
        let projection = try await repository.projection(identity: identity)
        guard let source = projection.messages.first(where: { $0.metadata.id == context.sourceMessageID }),
              WorkspaceToolRestrictions(userRequest: source.content).allows(operation: operation),
              let agentID = context.agentID, let agent = projection.agents.first(where: { $0.metadata.id == agentID }),
              ["resources", "read", "search", "list"].contains(operation) || agent.accessMode != .observe,
              context.allowedToolIDs.contains(tool),
              let record = projection.connections.first(where: { $0.metadata.id == id }),
              WorkspacePluginAccess.isActive(record, deviceID: identity.deviceID, projection: projection),
              WorkspacePluginAccess.externalTools(record.pluginId).contains(tool),
              try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection) != nil else { throw WorkspaceStorageError.permissionDenied }
        if let taskID = context.taskID {
            guard let task = projection.tasks.first(where: { $0.metadata.id == taskID }), task.execution.executorDeviceId == identity.deviceID,
                  !WorkspaceTaskService.terminal(task.state), task.state != .paused else { throw WorkspaceStorageError.permissionDenied }
        }
    }
    public func disconnect(_ id: UUID) async throws { try await WorkspaceConnectionService(repository: repository, identity: identity).disconnect(id) }
}
