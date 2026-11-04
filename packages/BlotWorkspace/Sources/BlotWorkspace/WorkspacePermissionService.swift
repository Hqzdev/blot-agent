import BlotDomain
import CryptoKit
import Foundation

public struct WorkspaceCommandOutcome: Equatable, Sendable {
    public let resultID: UUID
    /// Only the transaction that first claims an invocation may start its external request.
    public let applied: Bool
}

public struct WorkspaceActionDraft: Codable, Equatable, Sendable {
    public let toolID: String
    public let resource: String
    public let parametersJSON: String
    public let consequences: String
    public init(toolID: String, resource: String, parametersJSON: String, consequences: String) {
        self.toolID = toolID; self.resource = resource; self.parametersJSON = parametersJSON; self.consequences = consequences
    }
}

/// A grant binds one exact preparation. Neither instructions nor model text can supply a grant.
public struct WorkspacePermissionService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func prepare(commandID: UUID, taskID: UUID, actionID: UUID? = nil, expectedVersion: Int = 0,
        draft: WorkspaceActionDraft, expiresAt: Date, now: Date = Date()) async throws -> UUID {
        guard !draft.toolID.isEmpty, !draft.resource.isEmpty, !draft.consequences.isEmpty,
              draft.parametersJSON.utf8.count <= 48 * 1024, draft.resource.utf8.count <= 2048,
              draft.consequences.utf8.count <= 4096, expiresAt > now, expiresAt.timeIntervalSince(now) <= 3600 else {
            throw WorkspaceStorageError.invalidParameters
        }
        let parameters = try JSONFields.string(JSONFields.object(draft.parametersJSON))
        struct Input: Encodable { let taskID: UUID; let actionID: UUID?; let expectedVersion: Int; let draft: WorkspaceActionDraft; let expiresAt: Date }
        let command = try WorkspaceCommand(type: "action.prepare", workspaceID: identity.workspaceID,
            payload: Input(taskID: taskID, actionID: actionID, expectedVersion: expectedVersion, draft: draft, expiresAt: expiresAt)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let task = try Self.activeTask(tx, id: taskID)
            guard task.execution.executorDeviceId == tx.identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
            guard let configurationID = task.configurationId else { throw WorkspaceStorageError.invalidRecord }
            let configuration = try tx.require(BlotV3.AgentConfigurationRevision.self, id: configurationID)
            guard configuration.toolIds.contains(draft.toolID) else { throw WorkspaceStorageError.permissionDenied }
            let id = actionID ?? commandID
            let digest = try Self.digest(preparationID: commandID, actionID: id, execution: task.execution, toolID: draft.toolID,
                resource: draft.resource, parameters: parameters, consequences: draft.consequences, expiresAt: expiresAt)
            let old = try actionID.map { try tx.require(BlotV3.PreparedAction.self, id: $0, version: expectedVersion) }
            if let old {
                guard old.execution.taskId == taskID, [.prepared, .waiting_approval, .approved, .denied, .expired].contains(old.state) else {
                    throw WorkspaceStorageError.permissionDenied
                }
                try Self.revokeGrants(tx, actionID: id, now: now)
            } else if expectedVersion != 0 { throw WorkspaceStorageError.versionConflict }
            let action = try BlotV3.PreparedAction(metadata: tx.metadata(id: id, now: now, replacing: old?.metadata), execution: task.execution,
                toolId: draft.toolID, resource: draft.resource, parameters: parameters, digest: digest,
                consequences: draft.consequences, expiresAt: expiresAt, state: .waiting_approval, preparationId: commandID)
            try tx.put(action, expectedVersion: expectedVersion)
            return id
        }
    }

    public func approve(commandID: UUID, actionID: UUID, expectedVersion: Int, digest: String, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let actionID: UUID; let expectedVersion: Int; let digest: String }
        let command = try WorkspaceCommand(type: "action.approve", workspaceID: identity.workspaceID,
            payload: Input(actionID: actionID, expectedVersion: expectedVersion, digest: digest)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let action = try tx.require(BlotV3.PreparedAction.self, id: actionID, version: expectedVersion)
            _ = try Self.activeTask(tx, id: action.execution.taskId)
            guard try Self.validDigest(action), action.digest == digest, action.expiresAt > now, [.waiting_approval, .prepared].contains(action.state) else {
                throw WorkspaceStorageError.permissionDenied
            }
            let grant = try BlotV3.ApprovalGrant(metadata: tx.metadata(id: commandID, now: now), kind: .once, actionId: actionID,
                operationClass: action.toolId, scope: "exact-preparation", resource: action.resource, digest: digest,
                expiresAt: action.expiresAt, revoked: false)
            try tx.put(grant, expectedVersion: 0)
            try Self.setAction(tx, action, state: .approved, now: now)
            return commandID
        }
    }

    public func deny(commandID: UUID, actionID: UUID, expectedVersion: Int, now: Date = Date()) async throws {
        struct Input: Encodable { let actionID: UUID; let expectedVersion: Int }
        let command = try WorkspaceCommand(type: "action.deny", workspaceID: identity.workspaceID,
            payload: Input(actionID: actionID, expectedVersion: expectedVersion)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let action = try tx.require(BlotV3.PreparedAction.self, id: actionID, version: expectedVersion)
            guard [.prepared, .waiting_approval, .approved].contains(action.state) else { throw WorkspaceStorageError.permissionDenied }
            try Self.revokeGrants(tx, actionID: actionID, now: now)
            try Self.setAction(tx, action, state: .denied, now: now)
            return actionID
        }
    }

    public func begin(actionID: UUID, digest: String, now: Date = Date()) async throws -> WorkspaceCommandOutcome {
        struct Input: Encodable { let actionID: UUID; let digest: String }
        let invocationID = WorkspaceLogicalID.make(kind: "ToolInvocation", workspaceID: identity.workspaceID, parts: [actionID.uuidString, digest])
        let command = try WorkspaceCommand(type: "action.begin", workspaceID: identity.workspaceID, payload: Input(actionID: actionID, digest: digest)).data()
        return try await repository.executeOutcome(commandID: invocationID, command: command, identity: identity) { tx in
            let action = try tx.require(BlotV3.PreparedAction.self, id: actionID)
            let task = try Self.activeTask(tx, id: action.execution.taskId)
            guard try Self.validDigest(action), task.execution.executorDeviceId == tx.identity.deviceID, action.state == .approved,
                  action.expiresAt > now, action.digest == digest else { throw WorkspaceStorageError.permissionDenied }
            guard try tx.records(BlotV3.ApprovalGrant.self).contains(where: {
                $0.kind == .once && $0.actionId == actionID && !$0.revoked && $0.digest == digest && $0.resource == action.resource &&
                $0.operationClass == action.toolId && ($0.expiresAt.map { $0 > now } ?? false)
            }) else { throw WorkspaceStorageError.permissionDenied }
            try Self.revokeGrants(tx, actionID: actionID, now: now)
            let invocation = try BlotV3.ToolInvocation(metadata: tx.metadata(id: invocationID, now: now), execution: task.execution,
                preparedActionId: actionID, state: .running)
            try tx.put(invocation, expectedVersion: 0)
            try Self.setAction(tx, action, state: .running, now: now)
            return invocationID
        }
    }

    public func finish(commandID: UUID, invocationID: UUID, state: BlotV3.ActionState, externalID: String? = nil,
        result: String? = nil, now: Date = Date()) async throws {
        guard [.succeeded, .failed, .unknown].contains(state), (result?.utf8.count ?? 0) <= 64 * 1024 else { throw WorkspaceStorageError.invalidParameters }
        struct Input: Encodable { let invocationID: UUID; let state: BlotV3.ActionState; let externalID: String?; let result: String? }
        let command = try WorkspaceCommand(type: "action.finish", workspaceID: identity.workspaceID,
            payload: Input(invocationID: invocationID, state: state, externalID: externalID, result: result)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let old = try tx.require(BlotV3.ToolInvocation.self, id: invocationID)
            guard old.execution.executorDeviceId == tx.identity.deviceID else { throw WorkspaceStorageError.permissionDenied }
            if ![.running, .unknown].contains(old.state) {
                guard old.state == state, old.externalId == externalID, old.result == result else { throw WorkspaceStorageError.commandConflict }
                return invocationID
            }
            let updated = try BlotV3.ToolInvocation(metadata: tx.metadata(id: invocationID, now: now, replacing: old.metadata),
                execution: old.execution, preparedActionId: old.preparedActionId, state: state, externalId: externalID, result: result)
            try tx.put(updated, expectedVersion: old.metadata.version)
            let action = try tx.require(BlotV3.PreparedAction.self, id: old.preparedActionId)
            try Self.setAction(tx, action, state: state, now: now)
            return invocationID
        }
    }

    public func recoverUncertainInvocations(now: Date = Date()) async throws {
        for invocation in try await repository.records(BlotV3.ToolInvocation.self, workspaceID: identity.workspaceID)
            where invocation.execution.executorDeviceId == identity.deviceID && invocation.state == .running {
            try await finish(commandID: WorkspaceLogicalID.make(kind: "InvocationRecovery", workspaceID: identity.workspaceID,
                parts: [invocation.metadata.id.uuidString]), invocationID: invocation.metadata.id, state: .unknown, now: now)
        }
    }

    private static func activeTask(_ tx: WorkspaceTransaction, id: UUID) throws -> BlotV3.Task {
        let task = try tx.require(BlotV3.Task.self, id: id)
        guard !WorkspaceTaskService.terminal(task.state) else { throw WorkspaceStorageError.permissionDenied }
        return task
    }
    private static func revokeGrants(_ tx: WorkspaceTransaction, actionID: UUID, now: Date) throws {
        for grant in try tx.records(BlotV3.ApprovalGrant.self) where grant.actionId == actionID && !grant.revoked {
            let revoked = try BlotV3.ApprovalGrant(metadata: tx.metadata(id: grant.metadata.id, now: now, replacing: grant.metadata),
                kind: grant.kind, actionId: grant.actionId, operationClass: grant.operationClass, scope: grant.scope,
                resource: grant.resource, digest: grant.digest, expiresAt: grant.expiresAt, revoked: true)
            try tx.put(revoked, expectedVersion: grant.metadata.version)
        }
    }
    private static func setAction(_ tx: WorkspaceTransaction, _ action: BlotV3.PreparedAction, state: BlotV3.ActionState, now: Date) throws {
        let updated = try BlotV3.PreparedAction(metadata: tx.metadata(id: action.metadata.id, now: now, replacing: action.metadata),
            execution: action.execution, toolId: action.toolId, resource: action.resource, parameters: action.parameters,
            digest: action.digest, consequences: action.consequences, expiresAt: action.expiresAt, state: state, preparationId: action.preparationId)
        try tx.put(updated, expectedVersion: action.metadata.version)
    }

    private static func validDigest(_ action: BlotV3.PreparedAction) throws -> Bool {
        guard let preparationID = action.preparationId else { return false }
        return try action.digest == digest(preparationID: preparationID, actionID: action.metadata.id, execution: action.execution,
            toolID: action.toolId, resource: action.resource, parameters: JSONFields.string(JSONFields.object(action.parameters)),
            consequences: action.consequences, expiresAt: action.expiresAt)
    }

    private static func digest(preparationID: UUID, actionID: UUID, execution: BlotV3.ExecutionContext, toolID: String,
        resource: String, parameters: String, consequences: String, expiresAt: Date) throws -> String {
        struct Binding: Encodable {
            let preparationID: UUID; let actionID: UUID; let taskID: UUID; let executorDeviceID: UUID
            let toolID: String; let resource: String; let parameters: String; let consequences: String; let expiresAt: Date
        }
        let binding = Binding(preparationID: preparationID, actionID: actionID, taskID: execution.taskId,
            executorDeviceID: execution.executorDeviceId, toolID: toolID, resource: resource, parameters: parameters,
            consequences: consequences, expiresAt: expiresAt)
        return SHA256.hash(data: try WorkspaceCoding.encode(binding)).map { String(format: "%02x", $0) }.joined()
    }
}
