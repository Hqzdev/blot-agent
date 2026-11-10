import BlotDomain
import Foundation

public enum WorkspaceSkillError: Error, Equatable, Sendable {
    case invalidTemplate, archived, notAssigned, toolsUnavailable, revisionUnavailable, wrongConversation
}

/// A skill-use rule authorizes a saved routine, never its external tools.
public struct WorkspaceSkillAssignment: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let version: Int
    public let skillID: UUID
    public let agentID: UUID
    public let assigned: Bool
}

public enum WorkspaceSkillAccess {
    public static let operation = "skill.use"
    public static func assignments(_ grants: [BlotV3.ApprovalGrant], now: Date = Date()) -> [WorkspaceSkillAssignment] {
        grants.compactMap { grant in
            guard grant.kind == .rule, grant.operationClass == operation, grant.actionId == nil,
                  grant.resource.hasPrefix("skill:"), grant.scope.hasPrefix("agent:"),
                  let skillID = UUID(uuidString: String(grant.resource.dropFirst(6))),
                  let agentID = UUID(uuidString: String(grant.scope.dropFirst(6))) else { return nil }
            return .init(id: grant.metadata.id, version: grant.metadata.version, skillID: skillID, agentID: agentID,
                assigned: !grant.revoked && (grant.expiresAt.map { $0 > now } ?? true))
        }
    }
    public static func require(skillID: UUID, agentID: UUID, projection: WorkspaceProjection) throws {
        guard let skill = projection.skills.first(where: { $0.metadata.id == skillID }) else { throw WorkspaceStorageError.missingRecord }
        guard !skill.archived else { throw WorkspaceSkillError.archived }
        guard !projection.conflicts.contains(where: { !$0.resolved && $0.recordKind == "Skill" && $0.recordId == skillID }) else { throw WorkspaceStorageError.unresolvedConflict }
        let matches = assignments(projection.grants).filter { $0.skillID == skillID && $0.agentID == agentID }
        guard !projection.conflicts.contains(where: { conflict in
            !conflict.resolved && conflict.recordKind == "ApprovalGrant" && matches.contains { $0.id == conflict.recordId }
        }) else { throw WorkspaceStorageError.unresolvedConflict }
        guard matches.contains(where: \.assigned) else { throw WorkspaceSkillError.notAssigned }
    }
    public static func internalToolIDs(agentID: UUID?, projection: WorkspaceProjection) -> Set<String> {
        guard let agentID else { return [] }
        let assigned = Set(assignments(projection.grants).filter { $0.agentID == agentID && $0.assigned }.map(\.skillID))
        return projection.skills.contains(where: { assigned.contains($0.metadata.id) && !$0.archived }) ? ["skill_list", "skill_run"] : []
    }
    static func require(revision: BlotV3.SkillRevision, agentID: UUID, configuration: BlotV3.AgentConfigurationRevision,
                        projection: WorkspaceProjection) throws {
        try require(skillID: revision.skillId, agentID: agentID, projection: projection)
        guard Set(revision.toolIds).isSubset(of: Set(configuration.toolIds)) else { throw WorkspaceSkillError.toolsUnavailable }
    }
    static func require(revisionID: UUID, agentID: UUID, tx: WorkspaceTransaction) throws {
        let projection = try projection(tx)
        guard let configuration = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection) else { throw WorkspaceStorageError.missingRecord }
        let revision = try tx.require(BlotV3.SkillRevision.self, id: revisionID)
        try require(revision: revision, agentID: agentID, configuration: configuration, projection: projection)
    }
    private static func projection(_ tx: WorkspaceTransaction) throws -> WorkspaceProjection {
        var result = WorkspaceProjection()
        result.agents = try tx.records(BlotV3.AgentProfile.self)
        result.configurations = try tx.records(BlotV3.AgentConfigurationRevision.self)
        result.skills = try tx.records(BlotV3.Skill.self)
        result.grants = try tx.records(BlotV3.ApprovalGrant.self)
        result.conflicts = try tx.records(BlotV3.ConflictingRevision.self)
        return result
    }
}

public struct WorkspaceSkillAssignmentService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }
    public func set(commandID: UUID, skillID: UUID, agentID: UUID, assigned: Bool, expectedVersion: Int) async throws {
        struct Input: Encodable { let skillID: UUID; let agentID: UUID; let assigned: Bool; let expectedVersion: Int }
        let command = try WorkspaceCommand(type: "skill.assign", workspaceID: identity.workspaceID,
            payload: Input(skillID: skillID, agentID: agentID, assigned: assigned, expectedVersion: expectedVersion)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let skill = try tx.require(BlotV3.Skill.self, id: skillID)
            _ = try tx.require(BlotV3.AgentProfile.self, id: agentID)
            try tx.requireResolved(kind: "Skill", id: skillID)
            try tx.requireResolved(kind: "AgentProfile", id: agentID)
            guard !assigned || !skill.archived else { throw WorkspaceSkillError.archived }
            let id = WorkspaceLogicalID.make(kind: "SkillAssignment", workspaceID: identity.workspaceID, parts: [skillID.uuidString, agentID.uuidString])
            try tx.requireResolved(kind: "ApprovalGrant", id: id)
            let old = try tx.record(BlotV3.ApprovalGrant.self, id: id)
            guard (old?.metadata.version ?? 0) == expectedVersion else { throw WorkspaceStorageError.versionConflict }
            let grant = try BlotV3.ApprovalGrant(metadata: tx.metadata(id: id, now: Date(), replacing: old?.metadata), kind: .rule,
                operationClass: WorkspaceSkillAccess.operation, scope: "agent:" + agentID.uuidString,
                resource: "skill:" + skillID.uuidString, revoked: !assigned)
            try tx.put(grant, expectedVersion: expectedVersion)
            return id
        }
    }
}
