import BlotDomain
import Foundation

public struct WorkspaceCustomRule: Codable, Equatable, Sendable, Identifiable {
    public enum Decision: String, Codable, CaseIterable, Sendable { case askFirst, allowAutomatically }
    public let id: UUID
    public let version: Int
    public var name: String
    public var toolID: String
    public var resource: String
    public var agentID: UUID?
    public var decision: Decision
    public init(id: UUID = UUID(), version: Int = 0, name: String, toolID: String, resource: String = "", agentID: UUID? = nil, decision: Decision = .askFirst) {
        self.id = id; self.version = version; self.name = name; self.toolID = toolID; self.resource = resource; self.agentID = agentID; self.decision = decision
    }
}

/// Uses an existing typed grant record so older replicas can preserve rules without executing them.
public struct WorkspaceRuleService: Sendable {
    private static let operation = "workspace.custom-rule"
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }
    public func rules() async throws -> [WorkspaceCustomRule] {
        Self.decode(try await repository.projection(identity: identity).grants)
    }
    private static func decode(_ grants: [BlotV3.ApprovalGrant]) -> [WorkspaceCustomRule] {
        grants.compactMap { grant in
            guard grant.kind == .rule, !grant.revoked, grant.expiresAt.map({ $0 > Date() }) ?? true, grant.operationClass == operation,
                  let data = grant.scope.data(using: .utf8),
                  var rule = try? JSONDecoder().decode(WorkspaceCustomRule.self, from: data),
                  grant.resource == rule.toolID, rule.id == grant.metadata.id else { return nil }
            rule = .init(id: rule.id, version: grant.metadata.version, name: rule.name, toolID: rule.toolID, resource: rule.resource, agentID: rule.agentID, decision: rule.decision)
            return rule
        }
    }
    public func save(_ rule: WorkspaceCustomRule) async throws {
        guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rule.name.utf8.count <= 800,
              rule.toolID.range(of: #"^[A-Za-z0-9_.-]{1,200}$"#, options: .regularExpression) != nil,
              rule.resource.utf8.count <= 2048 else { throw WorkspaceStorageError.invalidParameters }
        let command = try WorkspaceCommand(type: "permission.rule.save", workspaceID: identity.workspaceID, payload: rule).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            if let agent = rule.agentID { _ = try tx.require(BlotV3.AgentProfile.self, id: agent) }
            let old = try tx.record(BlotV3.ApprovalGrant.self, id: rule.id)
            guard old == nil || old?.operationClass == Self.operation, old?.metadata.version ?? 0 == rule.version else { throw WorkspaceStorageError.versionConflict }
            let grant = try BlotV3.ApprovalGrant(metadata: tx.metadata(id: rule.id, now: Date(), replacing: old?.metadata), kind: .rule,
                operationClass: Self.operation, scope: String(decoding: JSONEncoder().encode(rule), as: UTF8.self), resource: rule.toolID, revoked: false)
            try tx.put(grant, expectedVersion: rule.version)
            return rule.id
        }
    }
    public func delete(_ rule: WorkspaceCustomRule) async throws {
        let command = try WorkspaceCommand(type: "permission.rule.delete", workspaceID: identity.workspaceID, payload: rule).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let grant = try tx.require(BlotV3.ApprovalGrant.self, id: rule.id, version: rule.version)
            guard grant.operationClass == Self.operation else { throw WorkspaceStorageError.permissionDenied }
            try tx.delete(grant); return rule.id
        }
    }
    public func requiresReview(toolID: String, resource: String, agentID: UUID?, default fallback: Bool, mandatory: Bool = false) async throws -> Bool {
        if mandatory { return true }
        let matches = try await rules().filter { $0.toolID == toolID && ($0.resource.isEmpty || $0.resource == resource) && ($0.agentID == nil || $0.agentID == agentID) }
        if matches.contains(where: { $0.decision == .askFirst }) { return true }
        if matches.contains(where: { $0.decision == .allowAutomatically }) { return false }
        return fallback
    }
}
