import BlotDomain
import Foundation

/// Persists user-selected device resources and assignments together with agent tool revisions.
public struct WorkspaceConnectionService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    @discardableResult
    public func save(pluginID: String, name: String, resources: [String], agentIDs: [UUID], toolIDs: [String]) async throws -> UUID {
        guard pluginID.hasPrefix("apple."), !agentIDs.isEmpty, !resources.isEmpty,
              Set(resources).count == resources.count, Set(agentIDs).count == agentIDs.count else { throw WorkspaceStorageError.invalidParameters }
        struct Input: Encodable { let pluginID: String; let resources: [String]; let agents: [UUID] }
        let commandID = UUID()
        let command = try WorkspaceCommand(type: "connection.save", workspaceID: identity.workspaceID,
            payload: Input(pluginID: pluginID, resources: resources, agents: agentIDs)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let old = try tx.records(BlotV3.Connection.self).first { $0.pluginId == pluginID && $0.deviceId == identity.deviceID }
            let id = old?.metadata.id ?? commandID
            if old != nil { try tx.requireResolved(kind: "Connection", id: id) }
            let connection = try BlotV3.Connection(metadata: tx.metadata(id: id, now: Date(), replacing: old?.metadata),
                service: name, accountName: name, scopes: ["read", "create", "update"], state: .connected,
                deviceId: identity.deviceID, pluginId: pluginID, resourceIds: resources, agentIds: agentIDs,
                allowedOperations: ["read", "create", "update"])
            for agentID in agentIDs {
                try tx.requireResolved(kind: "AgentProfile", id: agentID)
                let agent = try tx.require(BlotV3.AgentProfile.self, id: agentID)
                let oldConfiguration = try agent.configurationId.map { try tx.require(BlotV3.AgentConfigurationRevision.self, id: $0) }
                    ?? tx.records(BlotV3.AgentConfigurationRevision.self).filter { $0.agentId == agentID }.max { $0.revision < $1.revision }
                guard let oldConfiguration else { throw WorkspaceStorageError.missingRecord }
                let revisionID = UUID()
                let configuration = try BlotV3.AgentConfigurationRevision(metadata: tx.metadata(id: revisionID, now: Date()), agentId: agentID,
                    revision: agent.metadata.version + 1, instructions: oldConfiguration.instructions,
                    toolIds: Array(Set(oldConfiguration.toolIds + toolIDs)).sorted(), modelId: oldConfiguration.modelId)
                let updated = try BlotV3.AgentProfile(metadata: tx.metadata(id: agentID, now: Date(), replacing: agent.metadata),
                    name: agent.name, roleId: agent.roleId, avatarShape: agent.avatarShape, avatarColor: agent.avatarColor,
                    instructions: agent.instructions, modelId: agent.modelId, accessMode: agent.accessMode, configurationId: revisionID)
                try tx.put(configuration, expectedVersion: 0)
                try tx.put(updated, expectedVersion: agent.metadata.version)
            }
            for grant in try tx.records(BlotV3.ApprovalGrant.self) where grant.kind == .rule && grant.resource == id.uuidString {
                try tx.delete(grant)
            }
            let grant = try BlotV3.ApprovalGrant(metadata: tx.metadata(id: UUID(), now: Date()), kind: .rule,
                operationClass: "apple.resource.write", scope: pluginID, resource: id.uuidString, revoked: false)
            try tx.put(grant, expectedVersion: 0)
            try tx.put(connection, expectedVersion: old?.metadata.version ?? 0)
            return id
        }
    }

    public func disconnect(_ id: UUID) async throws {
        struct Input: Encodable { let id: UUID }
        let command = try WorkspaceCommand(type: "connection.disconnect", workspaceID: identity.workspaceID, payload: Input(id: id)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let connection = try tx.require(BlotV3.Connection.self, id: id)
            guard connection.deviceId == identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
            for grant in try tx.records(BlotV3.ApprovalGrant.self) where grant.kind == .rule && grant.resource == id.uuidString { try tx.delete(grant) }
            try tx.delete(connection)
            return id
        }
    }
}
