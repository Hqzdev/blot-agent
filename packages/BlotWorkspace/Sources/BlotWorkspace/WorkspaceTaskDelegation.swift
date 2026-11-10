import BlotDomain
import Foundation

public struct WorkspaceTaskDelegation: Sendable {
    private struct Request: Codable, Equatable {
        let ownerID: UUID; let workspaceID: UUID; let taskID: UUID; let conversationID: UUID; let originID: UUID; let executorID: UUID
        let configurationID: UUID; let goal: String; let budget: Int; let pairingID: UUID; let expires: Date
        let projectID: UUID?
    }
    private struct Proof: Codable { let request: Request; let signature: Data }
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let authority: WorkspaceDeviceAuthority
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, authority: WorkspaceDeviceAuthority) {
        self.repository = repository; self.identity = identity; self.authority = authority
    }
    public func create(commandID: UUID, conversationID: UUID, agentID: UUID, executorID: UUID, goal: String, projectID: UUID? = nil, budget: Int = 20_000, now: Date = Date()) async throws -> UUID {
        guard authority.identity == identity else { throw WorkspaceStorageError.permissionDenied }
        let peer = try await authority.peer(executorID)
        guard peer.kind == .desktop, executorID != identity.deviceID, budget > 0, budget <= 1_000_000, goal.utf8.count <= 32_768 else { throw WorkspaceStorageError.invalidParameters }
        let projection = try await repository.projection(identity: identity)
        guard let configuration = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection),
              let chat = projection.conversations.first(where: { $0.metadata.id == conversationID }), !chat.archived,
              chat.kind != .group && chat.agentId == agentID else { throw WorkspaceStorageError.permissionDenied }
        let request = Request(ownerID: identity.ownerID, workspaceID: identity.workspaceID, taskID: commandID, conversationID: conversationID,
            originID: identity.deviceID, executorID: executorID, configurationID: configuration.metadata.id, goal: goal, budget: budget,
            pairingID: peer.pairingID, expires: Date(timeIntervalSince1970: floor(now.addingTimeInterval(7 * 86_400).timeIntervalSince1970)), projectID: projectID)
        let proof = Proof(request: request, signature: try await authority.signDelegation(WorkspaceCoding.encode(request), version: projectID == nil ? 1 : 2))
        let json = String(decoding: try WorkspaceCoding.encode(proof), as: UTF8.self)
        struct Input: Encodable { let conversationID: UUID; let agentID: UUID; let executorID: UUID; let goal: String; let budget: Int; let projectID: UUID? }
        let command = try WorkspaceCommand(type: "task.delegate", workspaceID: identity.workspaceID, payload: Input(conversationID: conversationID, agentID: agentID, executorID: executorID, goal: goal, budget: budget, projectID: projectID)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let agent = try tx.require(BlotV3.AgentProfile.self, id: agentID)
            guard agent.configurationId == nil || agent.configurationId == configuration.metadata.id else { throw WorkspaceStorageError.versionConflict }
            let id = try WorkspaceTaskService.insert(tx, taskID: commandID, conversationID: conversationID, agentID: agentID, goal: goal,
                executorDeviceID: executorID, parentTaskID: nil, skillRevisionID: nil, budgetTokenLimit: budget, projectID: projectID, authorizationJSON: json, now: now)
            guard try tx.require(BlotV3.Task.self, id: id).configurationId == configuration.metadata.id else { throw WorkspaceStorageError.versionConflict }
            return id
        }
    }
    public func authorize(_ task: BlotV3.Task, now: Date = Date()) async throws {
        guard authority.identity == identity, task.metadata.ownerId == identity.ownerID, task.metadata.workspaceId == identity.workspaceID,
              task.execution.executorDeviceId == identity.deviceID, task.execution.originDeviceId != identity.deviceID,
              task.executionMode == .delegated, task.execution.taskId == task.metadata.id,
              task.parentTaskId == nil, task.skillRevisionId == nil,
              let raw = task.authorizationJSON, raw.utf8.count <= 262_144 else { throw WorkspaceStorageError.permissionDenied }
        let proof = try WorkspaceCoding.decode(Proof.self, from: Data(raw.utf8)), r = proof.request
        let peer = try await authority.peer(task.execution.originDeviceId)
        guard peer.kind == .phone, r.ownerID == identity.ownerID, r.workspaceID == identity.workspaceID, r.taskID == task.metadata.id,
              r.conversationID == task.conversationId, r.originID == task.execution.originDeviceId, r.executorID == identity.deviceID,
              r.configurationID == task.configurationId, r.goal == task.goal, r.budget == task.budgetTokenLimit, r.projectID == task.projectId,
              r.pairingID == peer.pairingID, r.expires > now, r.expires <= now.addingTimeInterval(7 * 86_400 + 300), task.execution.revision == 1 else { throw WorkspaceStorageError.permissionDenied }
        try WorkspaceDeviceKeys.verifyProof(proof.signature, signingKey: peer.signingKey, domain: "BLOT-TASK-DELEGATION-" + (r.projectID == nil ? "1" : "2"),
            ids: [identity.ownerID, identity.workspaceID], values: [WorkspaceCoding.encode(r)])
    }
}
