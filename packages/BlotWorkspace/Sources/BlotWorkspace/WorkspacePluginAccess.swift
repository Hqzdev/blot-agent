import BlotDomain
import Foundation

/// Plugin connections grant tools on their own device to every workspace agent.
public enum WorkspacePluginAccess {
    public static func isActive(_ connection: BlotV3.Connection, deviceID: UUID, projection: WorkspaceProjection) -> Bool {
        connection.deviceId == deviceID && connection.state == .connected
            && !projection.conflicts.contains { !$0.resolved && $0.recordKind == "Connection" && $0.recordId == connection.metadata.id }
    }

    public static func isActive(_ connection: BlotV3.McpConnection, deviceID: UUID, projection: WorkspaceProjection) -> Bool {
        isDeviceMCP(connection, deviceID: deviceID)
            && !projection.conflicts.contains { !$0.resolved && $0.recordKind == "McpConnection" && $0.recordId == connection.metadata.id }
    }

    public static func isAppleActive(_ connection: BlotV3.Connection, deviceID: UUID, projection: WorkspaceProjection) -> Bool {
        isActive(connection, deviceID: deviceID, projection: projection) && hasAppleGrant(connection, grants: projection.grants)
    }

    static func externalTools(_ pluginID: String?) -> Set<String> {
        guard let pluginID else { return [] }
        if let plugin = WorkspaceGooglePlugin(rawValue: pluginID) {
            return Set(WorkspaceGoogleCatalog.definitions.filter { WorkspaceGoogleCatalog.plugin($0.name) == plugin }.map(\.name) + ["google_accounts"])
        }
        if WorkspaceMessagingProvider(rawValue: pluginID) != nil {
            return Set(WorkspaceMessagingTools.catalog.map(\.name).filter { $0.hasPrefix(pluginID + "_") } + ["messaging_accounts"])
        }
        return []
    }

    static func isDeviceMCP(_ connection: BlotV3.McpConnection, deviceID: UUID) -> Bool {
        connection.state == .connected && connection.endpoint == "device:" + deviceID.uuidString
    }

    static func appleToolPrefix(_ pluginID: String?) -> String? {
        guard let pluginID, pluginID.hasPrefix("apple."), pluginID.count > 6 else { return nil }
        return "apple_" + pluginID.dropFirst(6) + "_"
    }

    static func hasAppleGrant(_ connection: BlotV3.Connection, grants: [BlotV3.ApprovalGrant]) -> Bool {
        grants.contains {
            $0.kind == .rule && !$0.revoked && $0.resource == connection.metadata.id.uuidString
                && $0.scope == connection.pluginId && $0.operationClass == "apple.resource.write"
        }
    }

    static func permitsPreparation(toolID: String, resource: String, in tx: WorkspaceTransaction) throws -> Bool {
        let parts = resource.split(separator: "/", maxSplits: 1)
        guard let first = parts.first, let id = UUID(uuidString: String(first)) else { return false }
        if parts.count == 1, toolID.hasPrefix("mcp_") {
            try tx.requireResolved(kind: "McpConnection", id: id)
            guard let record = try tx.record(BlotV3.McpConnection.self, id: id) else { return false }
            return isDeviceMCP(record, deviceID: tx.identity.deviceID) && record.toolIds.contains(toolID)
        }
        try tx.requireResolved(kind: "Connection", id: id)
        guard let connection = try tx.record(BlotV3.Connection.self, id: id),
              connection.deviceId == tx.identity.deviceID, connection.state == .connected else { return false }
        if parts.count == 1 { return externalTools(connection.pluginId).contains(toolID) }
        guard let prefix = appleToolPrefix(connection.pluginId), toolID.hasPrefix(prefix),
              ["create", "update", "delete", "move", "reply", "send", "run"].contains(String(toolID.dropFirst(prefix.count))),
              connection.resourceIds?.contains(String(parts[1])) == true else { return false }
        return try hasAppleGrant(connection, grants: tx.records(BlotV3.ApprovalGrant.self))
    }
}
