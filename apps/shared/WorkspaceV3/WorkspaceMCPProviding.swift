import BlotAppleIntegrations
import BlotWorkspace
import Foundation

@MainActor
protocol WorkspaceMCPProviding {
    func mcpService() async throws -> WorkspaceMCPService
}

extension LocalWorkspaceService: WorkspaceMCPProviding {
    func mcpService() async throws -> WorkspaceMCPService {
        if let mcp { return mcp }
        let identity = try await context()
        let service = WorkspaceMCPService(repository: repository, identity: identity, credentials: mcpCredentials)
        mcp = service
        return service
    }
    func mcpProvider() async throws -> WorkspaceRefreshingToolProvider {
        let interactions = appleIntegrations.interactions
        let service = try await mcpService()
        let confirm: @Sendable (String, String) async throws -> Bool = { title, details in
            try await interactions.confirm(title: title, details: details)
        }
        return WorkspaceRefreshingToolProvider(initial: try await service.provider(confirm: confirm), reload: {
            try await service.provider(confirm: confirm)
        })
    }
}

extension WorkspaceAccountApplicationService: WorkspaceMCPProviding {
    func mcpService() async throws -> WorkspaceMCPService {
        guard let workspace = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        return try await workspace.mcpService()
    }
}
