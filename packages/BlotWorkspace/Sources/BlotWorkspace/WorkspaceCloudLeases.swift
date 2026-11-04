import BlotDomain
import Foundation

public struct WorkspaceExecutionLease: Codable, Equatable, Sendable {
    public let taskID: UUID
    public let executorDeviceID: UUID
    public let holderID: UUID
    public let generation: Int64
    public let expiresAt: String
}

public struct WorkspaceCloudLeases: Sendable {
    private struct Registration: Encodable { let taskID: UUID; let executorDeviceID: UUID; let parentTaskID: UUID? }
    private struct Authority: Encodable { let taskID: UUID; let holderID: UUID; let generation: Int64 }
    private let http: WorkspaceCloudHTTP
    private let authorization: any WorkspaceCloudAuthorization
    private let identity: WorkspaceIdentity
    /// A fresh holder per process prevents two copies of one device's credentials sharing one lease.
    public let holderID: UUID
    public init(http: WorkspaceCloudHTTP, authorization: any WorkspaceCloudAuthorization, identity: WorkspaceIdentity, holderID: UUID = UUID()) {
        self.http = http; self.authorization = authorization; self.identity = identity; self.holderID = holderID
    }
    public func register(_ task: BlotV3.Task) async throws {
        guard task.metadata.workspaceId == identity.workspaceID, task.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.permissionDenied }
        try await http.empty(method: "POST", path: ["v1", "execution", "tasks"], body: JSONEncoder().encode(
            Registration(taskID: task.metadata.id, executorDeviceID: task.execution.executorDeviceId, parentTaskID: task.parentTaskId)), accessToken: authorization.accessToken())
    }
    public func acquire(taskID: UUID) async throws -> WorkspaceExecutionLease {
        struct Claim: Encodable { let taskID: UUID; let holderID: UUID }
        let lease = try await http.request(WorkspaceExecutionLease.self, method: "POST", path: ["v1", "execution", "acquire"],
            body: JSONEncoder().encode(Claim(taskID: taskID, holderID: holderID)), accessToken: authorization.accessToken())
        try validate(lease, taskID: taskID)
        return lease
    }
    public func renew(_ lease: WorkspaceExecutionLease) async throws -> WorkspaceExecutionLease {
        try validate(lease, taskID: lease.taskID)
        let renewed = try await http.request(WorkspaceExecutionLease.self, method: "POST", path: ["v1", "execution", "renew"],
            body: JSONEncoder().encode(Authority(taskID: lease.taskID, holderID: holderID, generation: lease.generation)), accessToken: authorization.accessToken())
        try validate(renewed, taskID: lease.taskID)
        guard renewed.generation == lease.generation else { throw WorkspaceStorageError.permissionDenied }
        return renewed
    }
    public func check(_ lease: WorkspaceExecutionLease) async throws { try await authority("check", lease: lease) }
    public func release(_ lease: WorkspaceExecutionLease) async throws { try await authority("release", lease: lease) }
    public func cancel(taskID: UUID) async throws {
        struct Cancel: Encodable { let taskID: UUID }
        try await http.empty(method: "POST", path: ["v1", "execution", "cancel"], body: JSONEncoder().encode(Cancel(taskID: taskID)), accessToken: authorization.accessToken())
    }
    public func beginExternalAction(_ lease: WorkspaceExecutionLease, actionID: UUID, digest: String) async throws {
        try validate(lease, taskID: lease.taskID)
        struct Action: Encodable { let taskID: UUID; let holderID: UUID; let generation: Int64; let actionID: UUID; let digest: String }
        try await http.empty(method: "POST", path: ["v1", "execution", "actions", "begin"], body: JSONEncoder().encode(
            Action(taskID: lease.taskID, holderID: holderID, generation: lease.generation, actionID: actionID, digest: digest)), accessToken: authorization.accessToken())
    }
    public func finishExternalAction(taskID: UUID, actionID: UUID, digest: String, state: BlotV3.ActionState) async throws {
        guard [.succeeded, .failed, .unknown].contains(state) else { throw WorkspaceStorageError.invalidParameters }
        struct Result: Encodable { let taskID: UUID; let actionID: UUID; let digest: String; let state: String }
        try await http.empty(method: "POST", path: ["v1", "execution", "actions", "finish"], body: JSONEncoder().encode(
            Result(taskID: taskID, actionID: actionID, digest: digest, state: state.rawValue)), accessToken: authorization.accessToken())
    }
    private func authority(_ operation: String, lease: WorkspaceExecutionLease) async throws {
        try validate(lease, taskID: lease.taskID)
        try await http.empty(method: "POST", path: ["v1", "execution", operation], body: JSONEncoder().encode(
            Authority(taskID: lease.taskID, holderID: holderID, generation: lease.generation)), accessToken: authorization.accessToken())
    }
    private func validate(_ lease: WorkspaceExecutionLease, taskID: UUID) throws {
        guard lease.taskID == taskID, lease.executorDeviceID == identity.deviceID, lease.holderID == holderID, lease.generation > 0 else {
            throw WorkspaceStorageError.permissionDenied
        }
    }
}
