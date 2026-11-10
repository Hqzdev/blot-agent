import BlotAppleIntegrations
import BlotDomain
import Foundation

@MainActor
protocol WorkspaceAppleIntegrationProviding {
    var appleIntegrations: AppleIntegrationController { get }
    func connectApple(_ plugin: ApplePluginID, resources: [String], agentIDs: [UUID]) async throws -> WorkspaceSnapshot
    func resolveAppleInvocation(_ id: UUID, succeeded: Bool) async throws -> WorkspaceSnapshot
    func disconnectApple(_ connection: BlotV3.Connection) async throws -> WorkspaceSnapshot
}
