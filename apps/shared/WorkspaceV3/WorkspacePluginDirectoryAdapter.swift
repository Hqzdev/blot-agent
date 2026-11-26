import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

@MainActor protocol WorkspacePluginProviding {
    func pluginDirectory() async throws -> any WorkspacePluginDirectory
}

@MainActor final class WorkspacePluginDirectoryAdapter: WorkspacePluginDirectory {
    private let workspace: LocalWorkspaceService
    init(workspace: LocalWorkspaceService) { self.workspace = workspace }
    func plugins() async throws -> [WorkspacePluginDescriptor] {
        PluginCatalog.all.map { plugin in
            let available = plugin.appleID?.available ?? (WorkspaceGooglePlugin(rawValue: plugin.id) != nil
                || WorkspaceMessagingProvider(rawValue: plugin.id) != nil || WorkspacePluginPreset.find(plugin.id) != nil)
            return .init(id: plugin.id, name: plugin.name, summary: plugin.summary, available: available)
        }
    }
    func isConnected(pluginID: String, agentID: UUID) async throws -> Bool {
        guard let plugin = PluginCatalog.all.first(where: { $0.id == pluginID }) else { return false }
        let identity = try await workspace.context()
        let projection = try await workspace.repository.projection(identity: identity)
        guard (try? WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection)) != nil else { return false }
        if WorkspacePluginPreset.find(pluginID) != nil {
            return try await workspace.mcpService().access().contains { access in
                (access.pluginID == pluginID || access.pluginID == nil && access.name == plugin.name)
                    && access.enabled && !access.selectedTools.isEmpty
                    && projection.mcpConnections.contains { record in
                        record.metadata.id == access.id && WorkspacePluginAccess.isActive(record, deviceID: identity.deviceID, projection: projection)
                    }
            }
        }
        let connections = projection.connections.filter {
            $0.pluginId == pluginID && WorkspacePluginAccess.isActive($0, deviceID: identity.deviceID, projection: projection)
        }
        if let apple = plugin.appleID {
            guard apple.available, let connection = connections.first(where: {
                WorkspacePluginAccess.isAppleActive($0, deviceID: identity.deviceID, projection: projection)
            }) else { return false }
            return await workspace.appleIntegrations.accessible(apple, resources: connection.resourceIds ?? [])
        }
        guard !connections.isEmpty else { return false }
        let connectionIDs = Set(connections.map(\.metadata.id))
        if let google = WorkspaceGooglePlugin(rawValue: pluginID) {
            return try await workspace.googleService().accounts().contains { $0.plugin == google && connectionIDs.contains($0.id) }
        }
        if let messaging = WorkspaceMessagingProvider(rawValue: pluginID) {
            return try await workspace.messagingService().accounts().contains { $0.provider == messaging && connectionIDs.contains($0.id) }
        }
        return false
    }
}

extension LocalWorkspaceService: WorkspacePluginProviding {
    func pluginDirectory() async throws -> any WorkspacePluginDirectory { WorkspacePluginDirectoryAdapter(workspace: self) }
}
extension WorkspaceAccountApplicationService: WorkspacePluginProviding {
    func pluginDirectory() async throws -> any WorkspacePluginDirectory {
        guard let service = workspaceCommands as? any WorkspacePluginProviding else { throw WorkspaceServiceError.unavailable }
        return try await service.pluginDirectory()
    }
}
