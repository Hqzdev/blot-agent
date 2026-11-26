import BlotDomain
import Foundation

/// Persists user-selected device resources for workspace agents.
public struct WorkspaceConnectionService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    @discardableResult
    public func save(pluginID: String, name: String, resources: [String]) async throws -> UUID {
        guard pluginID.hasPrefix("apple."), !resources.isEmpty,
              Set(resources).count == resources.count else { throw WorkspaceStorageError.invalidParameters }
        struct Input: Encodable { let pluginID: String; let resources: [String] }
        let commandID = UUID()
        let command = try WorkspaceCommand(type: "connection.save", workspaceID: identity.workspaceID,
            payload: Input(pluginID: pluginID, resources: resources)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let old = try tx.records(BlotV3.Connection.self).first { $0.pluginId == pluginID && $0.deviceId == identity.deviceID }
            let id = old?.metadata.id ?? commandID
            if old != nil { try tx.requireResolved(kind: "Connection", id: id) }
            let connection = try BlotV3.Connection(metadata: tx.metadata(id: id, now: Date(), replacing: old?.metadata),
                service: name, accountName: name, scopes: ["read", "create", "update"], state: .connected,
                deviceId: identity.deviceID, pluginId: pluginID, resourceIds: resources,
                allowedOperations: ["read", "create", "update"])
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
