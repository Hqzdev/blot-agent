import BlotDomain
import Foundation

public struct WorkspaceTaskService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func create(commandID: UUID, conversationID: UUID, agentID: UUID, goal: String, executorDeviceID: UUID,
                       parentTaskID: UUID? = nil, skillRevisionID: UUID? = nil, budgetTokenLimit: Int = 20_000, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable {
            let conversationID: UUID; let agentID: UUID; let goal: String; let executorDeviceID: UUID
            let parentTaskID: UUID?; let skillRevisionID: UUID?; let budgetTokenLimit: Int
        }
        let command = try WorkspaceCommand(type: "task.create", workspaceID: identity.workspaceID,
            payload: Input(conversationID: conversationID, agentID: agentID, goal: goal, executorDeviceID: executorDeviceID,
                parentTaskID: parentTaskID, skillRevisionID: skillRevisionID, budgetTokenLimit: budgetTokenLimit)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            return try Self.insert(tx, taskID: commandID, conversationID: conversationID, agentID: agentID, goal: goal,
                executorDeviceID: executorDeviceID, parentTaskID: parentTaskID, skillRevisionID: skillRevisionID,
                budgetTokenLimit: budgetTokenLimit, now: now)
        }
    }

    static func insert(_ tx: WorkspaceTransaction, taskID: UUID, conversationID: UUID, agentID: UUID, goal: String,
                       executorDeviceID: UUID, parentTaskID: UUID?, skillRevisionID: UUID?, budgetTokenLimit: Int, now: Date) throws -> UUID {
            guard budgetTokenLimit > 0 else { throw WorkspaceStorageError.invalidParameters }
            _ = try tx.require(BlotV3.Conversation.self, id: conversationID)
            let agent = try tx.require(BlotV3.AgentProfile.self, id: agentID)
            try tx.requireResolved(kind: "AgentProfile", id: agentID)
            guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceStorageError.invalidParameters }
            let configuration: BlotV3.AgentConfigurationRevision
            if let id = agent.configurationId { configuration = try tx.require(BlotV3.AgentConfigurationRevision.self, id: id) }
            else if let legacy = try tx.records(BlotV3.AgentConfigurationRevision.self).filter({ $0.agentId == agentID }).max(by: { $0.revision < $1.revision }) { configuration = legacy }
            else { throw WorkspaceStorageError.missingRecord }
            var taskBudget = budgetTokenLimit
            if let skillRevisionID { _ = try tx.require(BlotV3.SkillRevision.self, id: skillRevisionID) }
            if let parentTaskID {
                var parent = try tx.require(BlotV3.Task.self, id: parentTaskID)
                var depth = 1
                while true {
                    guard !Self.terminal(parent.state), parent.conversationId == conversationID,
                          parent.execution.executorDeviceId == executorDeviceID else { throw WorkspaceStorageError.permissionDenied }
                    taskBudget = min(taskBudget, parent.budgetTokenLimit ?? taskBudget)
                    guard let ancestor = parent.parentTaskId else { break }
                    depth += 1
                    guard depth <= 2 else { throw WorkspaceStorageError.invalidParameters }
                    parent = try tx.require(BlotV3.Task.self, id: ancestor)
                }
            }
            let execution = try BlotV3.ExecutionContext(executorDeviceId: executorDeviceID, originDeviceId: tx.identity.deviceID,
                taskId: taskID, revision: 1)
            let task = try BlotV3.Task(metadata: tx.metadata(id: taskID, now: now), execution: execution, projectId: nil,
                conversationId: conversationID, goal: goal, state: .queued, plan: [], configurationId: configuration.metadata.id,
                parentTaskId: parentTaskID, skillRevisionId: skillRevisionID, budgetTokenLimit: taskBudget,
                executionMode: executorDeviceID == tx.identity.deviceID ? .local_owned : .delegated)
            let sessionID = WorkspaceLogicalID.make(kind: "AgentSession", workspaceID: tx.identity.workspaceID, parts: [taskID.uuidString, agentID.uuidString])
            let parentSession = try parentTaskID.flatMap { parentID in try tx.records(BlotV3.AgentSession.self).first { $0.execution.taskId == parentID }?.metadata.id }
            let session = try BlotV3.AgentSession(metadata: tx.metadata(id: sessionID, now: now), execution: execution,
                agentId: agentID, configurationId: configuration.metadata.id, parentSessionId: parentSession, state: .created)
            try tx.put(task, expectedVersion: 0)
            try tx.put(session, expectedVersion: 0)
            return taskID
    }

    /// Completes a local action task only when its recorded invocations have a known successful outcome.
    public func completeActionTask(taskID: UUID) async throws {
        struct Input: Encodable { let taskID: UUID }
        let command = try WorkspaceCommand(type: "task.complete-action", workspaceID: identity.workspaceID, payload: Input(taskID: taskID)).data()
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            let task = try tx.require(BlotV3.Task.self, id: taskID)
            let invocations = try tx.records(BlotV3.ToolInvocation.self).filter { $0.execution.taskId == taskID }
            guard task.execution.executorDeviceId == identity.deviceID, !Self.terminal(task.state),
                  !invocations.isEmpty, invocations.allSatisfy({ $0.state == .succeeded }) else { throw WorkspaceStorageError.permissionDenied }
            let updated = try BlotV3.Task(metadata: tx.metadata(id: taskID, now: Date(), replacing: task.metadata),
                execution: task.execution, projectId: task.projectId, conversationId: task.conversationId, goal: task.goal,
                state: .completed, plan: task.plan, configurationId: task.configurationId, parentTaskId: task.parentTaskId,
                skillRevisionId: task.skillRevisionId, budgetTokenLimit: task.budgetTokenLimit, executionMode: task.executionMode)
            try tx.put(updated, expectedVersion: task.metadata.version)
            for session in try tx.records(BlotV3.AgentSession.self) where session.execution.taskId == taskID {
                let finished = try BlotV3.AgentSession(metadata: tx.metadata(id: session.metadata.id, now: Date(), replacing: session.metadata),
                    execution: session.execution, agentId: session.agentId, configurationId: session.configurationId,
                    parentSessionId: session.parentSessionId, state: .completed)
                try tx.put(finished, expectedVersion: session.metadata.version)
            }
            return taskID
        }
    }

    public func cancel(commandID: UUID, taskID: UUID, now: Date = Date()) async throws {
        struct Input: Encodable { let taskID: UUID }
        let command = try WorkspaceCommand(type: "task.cancel", workspaceID: identity.workspaceID, payload: Input(taskID: taskID)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            _ = try tx.require(BlotV3.Task.self, id: taskID)
            let tasks = try tx.records(BlotV3.Task.self)
            var family: Set<UUID> = [taskID]
            while true {
                let next = Set(tasks.filter { $0.parentTaskId.map(family.contains) ?? false }.map(\.metadata.id))
                let count = family.count; family.formUnion(next)
                if count == family.count { break }
            }
            for task in tasks where family.contains(task.metadata.id) && !Self.terminal(task.state) {
                let updated = try BlotV3.Task(metadata: tx.metadata(id: task.metadata.id, now: now, replacing: task.metadata),
                    execution: task.execution, projectId: task.projectId, conversationId: task.conversationId, goal: task.goal,
                    state: .canceled, plan: task.plan, configurationId: task.configurationId, parentTaskId: task.parentTaskId, skillRevisionId: task.skillRevisionId, budgetTokenLimit: task.budgetTokenLimit, executionMode: task.executionMode)
                try tx.put(updated, expectedVersion: task.metadata.version)
            }
            for session in try tx.records(BlotV3.AgentSession.self) where family.contains(session.execution.taskId) && ![.completed, .failed, .canceled].contains(session.state) {
                let updated = try BlotV3.AgentSession(metadata: tx.metadata(id: session.metadata.id, now: now, replacing: session.metadata),
                    execution: session.execution, agentId: session.agentId, configurationId: session.configurationId,
                    parentSessionId: session.parentSessionId, state: .canceled)
                try tx.put(updated, expectedVersion: session.metadata.version)
            }
            return taskID
        }
    }

    static func terminal(_ state: BlotV3.TaskState) -> Bool { [.completed, .failed, .canceled].contains(state) }
}
