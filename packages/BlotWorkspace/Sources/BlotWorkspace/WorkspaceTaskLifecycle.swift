import BlotDomain
import Foundation

/// Serializes task, session and schedule-run transitions in the same transaction.
public struct WorkspaceTaskLifecycle: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let authorize: (@Sendable (BlotV3.Task) async throws -> Void)?
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, authorize: (@Sendable (BlotV3.Task) async throws -> Void)? = nil) { self.repository = repository; self.identity = identity; self.authorize = authorize }

    public func claim(_ taskID: UUID) async throws -> Bool {
        if let task = try await repository.record(BlotV3.Task.self, id: taskID, workspaceID: identity.workspaceID), task.executionMode == .delegated {
            guard let authorize else { throw WorkspaceStorageError.permissionDenied }; try await authorize(task)
        }
        struct Input: Encodable { let taskID: UUID }
        let command = try WorkspaceCommand(type: "task.claim", workspaceID: identity.workspaceID, payload: Input(taskID: taskID)).data()
        do {
            _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
                let task = try tx.require(BlotV3.Task.self, id: taskID)
                try Self.requireLocal(task, identity: tx.identity)
                guard task.state == .queued, try tx.executionAdmitted(task) else { throw WorkspaceTaskExecutionError.notRunnable }
                let tasks = try tx.records(BlotV3.Task.self)
                guard !tasks.contains(where: { $0.conversationId == task.conversationId && $0.state == .running }),
                      !(try tx.records(BlotV3.Message.self)).contains(where: { $0.conversationId == task.conversationId && $0.role == .assistant && $0.delivery == .running }) else { throw WorkspaceTaskExecutionError.notRunnable }
                if let parentID = task.parentTaskId {
                    let parent = try tx.require(BlotV3.Task.self, id: parentID)
                    guard [.running, .completed].contains(parent.state) else { throw WorkspaceTaskExecutionError.notRunnable }
                }
                let sourceID = Self.sourceID(taskID: taskID, workspaceID: identity.workspaceID)
                if try tx.record(BlotV3.Message.self, id: sourceID) == nil {
                    let source = try BlotV3.Message(metadata: tx.metadata(id: sourceID, now: Date()), conversationId: task.conversationId,
                        role: .user, content: task.goal, delivery: .saved, commandId: taskID, artifactIds: [],
                        position: tx.nextMessagePosition(in: task.conversationId))
                    try tx.put(source, expectedVersion: 0)
                }
                try Self.setState(task, .running, tx: tx)
                return taskID
            }
            return true
        } catch WorkspaceTaskExecutionError.notRunnable { return false }
    }
    public func pause(commandID: UUID, taskID: UUID) async throws {
        try await transition(commandID: commandID, taskID: taskID, operation: "pause")
    }
    public func resume(commandID: UUID, taskID: UUID) async throws {
        // All task invocations must be resolved before a worker may continue.
        let projection = try await repository.projection(identity: identity)
        _ = try WorkspaceTaskCheckpoint(taskID: taskID, projection: projection)
        try await transition(commandID: commandID, taskID: taskID, operation: "resume")
    }
    public func finish(taskID: UUID, state: BlotV3.TaskState, expectedVersion: Int? = nil) async throws {
        guard [.completed, .failed, .interrupted, .waiting_user].contains(state) else { throw WorkspaceStorageError.invalidParameters }
        struct Input: Encodable { let taskID: UUID; let state: BlotV3.TaskState; let expectedVersion: Int? }
        let command = try WorkspaceCommand(type: "task.finish", workspaceID: identity.workspaceID, payload: Input(taskID: taskID, state: state, expectedVersion: expectedVersion)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let task = try tx.require(BlotV3.Task.self, id: taskID)
            try Self.requireLocal(task, identity: tx.identity)
            // A late worker cannot undo pause or cancellation.
            guard task.state == .running, expectedVersion == nil || task.metadata.version == expectedVersion else { return taskID }
            let unknown = try tx.records(BlotV3.ToolInvocation.self).contains { $0.execution.taskId == taskID && [.running, .unknown].contains($0.state) }
            try Self.setState(task, unknown ? .interrupted : state, tx: tx)
            return taskID
        }
    }
    public func recover() async throws {
        let projection = try await repository.projection(identity: identity)
        for task in projection.tasks where task.execution.executorDeviceId == identity.deviceID && (task.execution.originDeviceId == identity.deviceID || task.authorizationJSON != nil) && (task.executionMode == .local_owned || task.executionMode == .delegated) && [.running, .interrupted].contains(task.state) {
            guard !Self.isActionOnly(task, projection: projection), try await repository.executionAdmitted(task, identity: identity) else { continue }
            if task.executionMode == .delegated {
                guard let authorize else { continue }
                do { try await authorize(task) } catch { continue }
            }
            let checkpoint = try? WorkspaceTaskCheckpoint(taskID: task.metadata.id, projection: projection)
            let unknown = projection.invocations.contains { $0.execution.taskId == task.metadata.id && [.running, .unknown].contains($0.state) }
            let state: BlotV3.TaskState
            if unknown || checkpoint == nil { state = .interrupted }
            else if checkpoint?.hasFinalResponse == true { state = checkpoint?.hasFailedResults == true ? .failed : .completed }
            else { state = .queued }
            try await recover(task, state: state)
        }
    }
    public static func sourceID(taskID: UUID, workspaceID: UUID) -> UUID {
        WorkspaceLogicalID.make(kind: "TaskSource", workspaceID: workspaceID, parts: [taskID.uuidString])
    }
    static func isActionOnly(_ task: BlotV3.Task, projection: WorkspaceProjection) -> Bool {
        guard let workspaceID = task.metadata.workspaceId else { return true }
        return projection.actions.contains { $0.execution.taskId == task.metadata.id }
            && !projection.modelSteps.contains { $0.taskId == task.metadata.id }
            && !projection.messages.contains { $0.metadata.id == sourceID(taskID: task.metadata.id, workspaceID: workspaceID) }
    }
    private func recover(_ old: BlotV3.Task, state: BlotV3.TaskState) async throws {
        struct Input: Encodable { let id: UUID; let version: Int; let state: BlotV3.TaskState }
        let command = try WorkspaceCommand(type: "task.recover", workspaceID: identity.workspaceID, payload: Input(id: old.metadata.id, version: old.metadata.version, state: state)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let current = try tx.require(BlotV3.Task.self, id: old.metadata.id)
            guard current.metadata.version == old.metadata.version else { return old.metadata.id }
            try Self.setState(current, state, tx: tx)
            return old.metadata.id
        }
    }
    private func transition(commandID: UUID, taskID: UUID, operation: String) async throws {
        struct Input: Encodable { let taskID: UUID }
        let command = try WorkspaceCommand(type: "task." + operation, workspaceID: identity.workspaceID, payload: Input(taskID: taskID)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let task = try tx.require(BlotV3.Task.self, id: taskID)
            try Self.requireLocal(task, identity: tx.identity)
            guard !WorkspaceTaskService.terminal(task.state) else { throw WorkspaceTaskExecutionError.notRunnable }
            let invocations = try tx.records(BlotV3.ToolInvocation.self)
            guard operation != "resume" || !invocations.contains(where: { $0.execution.taskId == taskID && [.running, .unknown].contains($0.state) }) else {
                throw WorkspaceTaskExecutionError.uncertainToolResult
            }
            guard operation != "resume" || [.paused, .interrupted, .waiting_user, .queued].contains(task.state) else { throw WorkspaceTaskExecutionError.notRunnable }
            let tasks = try tx.records(BlotV3.Task.self)
            var family: Set<UUID> = [taskID]
            while true {
                let count = family.count
                family.formUnion(tasks.filter { $0.parentTaskId.map(family.contains) ?? false }.map(\.metadata.id))
                if count == family.count { break }
            }
            if operation == "resume", invocations.contains(where: { family.contains($0.execution.taskId) && [.running, .unknown].contains($0.state) }) {
                throw WorkspaceTaskExecutionError.uncertainToolResult
            }
            for member in tasks where family.contains(member.metadata.id) && !WorkspaceTaskService.terminal(member.state) {
                if operation == "resume", member.metadata.id != taskID && member.state != .paused { continue }
                try Self.setState(member, operation == "pause" ? .paused : .queued, tx: tx)
            }
            return taskID
        }
    }
    static func requireLocal(_ task: BlotV3.Task, identity: WorkspaceIdentity) throws {
        guard task.execution.executorDeviceId == identity.deviceID,
              (task.executionMode == .local_owned && task.execution.originDeviceId == identity.deviceID || task.executionMode == .delegated && task.execution.originDeviceId != identity.deviceID && task.authorizationJSON != nil) else { throw WorkspaceStorageError.permissionDenied }
    }
    static func setState(_ task: BlotV3.Task, _ state: BlotV3.TaskState, tx: WorkspaceTransaction) throws {
        guard task.state != state else { return }
        let now = Date()
        try tx.put(BlotV3.Task(metadata: tx.metadata(id: task.metadata.id, now: now, replacing: task.metadata),
            execution: task.execution, projectId: task.projectId, conversationId: task.conversationId, goal: task.goal,
            state: state, plan: task.plan, configurationId: task.configurationId, parentTaskId: task.parentTaskId,
            skillRevisionId: task.skillRevisionId, budgetTokenLimit: task.budgetTokenLimit, executionMode: task.executionMode, authorizationJSON: task.authorizationJSON), expectedVersion: task.metadata.version)
        let sessionState: BlotV3.SessionState
        switch state {
        case .running, .planning: sessionState = .running
        case .completed: sessionState = .completed
        case .failed: sessionState = .failed
        case .canceled: sessionState = .canceled
        case .paused: sessionState = .paused
        case .queued, .draft: sessionState = .created
        default: sessionState = .waiting_user
        }
        for session in try tx.records(BlotV3.AgentSession.self) where session.execution.taskId == task.metadata.id {
            try tx.put(BlotV3.AgentSession(metadata: tx.metadata(id: session.metadata.id, now: now, replacing: session.metadata),
                execution: session.execution, agentId: session.agentId, configurationId: session.configurationId,
                parentSessionId: session.parentSessionId, state: sessionState), expectedVersion: session.metadata.version)
        }
        for run in try tx.records(BlotV3.AutomationRun.self) where run.execution.taskId == task.metadata.id {
            try tx.put(BlotV3.AutomationRun(metadata: tx.metadata(id: run.metadata.id, now: now, replacing: run.metadata),
                execution: run.execution, automationId: run.automationId, scheduledAt: run.scheduledAt, state: state, trigger: run.trigger), expectedVersion: run.metadata.version)
        }
    }
}
