import BlotDomain
import Foundation

/// A partially replicated profile must wait for its exact revision before generation.
public struct WorkspaceAgentConfigurationResolver: Sendable {
    public init() {}

    public func resolve(agentID: UUID?, projection: WorkspaceProjection) throws -> BlotV3.AgentConfigurationRevision? {
        guard let agentID else { return nil }
        guard !projection.conflicts.contains(where: {
            !$0.resolved && $0.recordKind == "AgentProfile" && $0.recordId == agentID
        }) else { throw WorkspaceStorageError.unresolvedConflict }
        guard let profile = projection.agents.first(where: { $0.metadata.id == agentID }) else {
            throw WorkspaceStorageError.missingRecord
        }
        if let configurationID = profile.configurationId {
            guard let configuration = projection.configurations.first(where: {
                $0.metadata.id == configurationID && $0.agentId == agentID
            }) else { throw WorkspaceStorageError.missingRecord }
            return configuration
        }
        guard let legacy = projection.configurations.filter({ $0.agentId == agentID }).max(by: { $0.revision < $1.revision }) else {
            throw WorkspaceStorageError.missingRecord
        }
        return legacy
    }
}
