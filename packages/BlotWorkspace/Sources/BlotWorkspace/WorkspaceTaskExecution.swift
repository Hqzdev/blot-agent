import BlotDomain
import Foundation

/// One local task execution. Control state is durable; the queue owns cancellation of this operation.
public struct WorkspaceTaskExecution: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let pool: WorkspaceExecutorPool
    private let tools: WorkspaceToolRegistry
    private let maximumOutputTokens: Int
    private let authorize: (@Sendable (BlotV3.Task) async throws -> Void)?
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, pool: WorkspaceExecutorPool,
                tools: WorkspaceToolRegistry, maximumOutputTokens: Int = 2048, authorize: (@Sendable (BlotV3.Task) async throws -> Void)? = nil) {
        self.repository = repository; self.identity = identity; self.pool = pool; self.tools = tools
        self.maximumOutputTokens = maximumOutputTokens; self.authorize = authorize
    }
    public func run(taskID: UUID, model: any ChatModel, emit: @escaping @Sendable (BlotV3.Message) -> Void = { _ in }) async throws {
        try await run(taskID: taskID, makeModel: { _ in model }, emit: emit)
    }
    public func run(taskID: UUID, makeModel: @Sendable (String) async throws -> any ChatModel,
                    emit: @escaping @Sendable (BlotV3.Message) -> Void = { _ in }) async throws {
        let lifecycle = WorkspaceTaskLifecycle(repository: repository, identity: identity, authorize: authorize)
        guard try await lifecycle.claim(taskID) else { return }
        var executionVersion: Int?
        do {
            try _Concurrency.Task.checkCancellation()
            let projection = try await repository.projection(identity: identity)
            guard let task = projection.tasks.first(where: { $0.metadata.id == taskID }),
                  let configuration = projection.configurations.first(where: { $0.metadata.id == task.configurationId }),
                  let source = projection.messages.first(where: { $0.metadata.id == WorkspaceTaskLifecycle.sourceID(taskID: taskID, workspaceID: identity.workspaceID) }) else { throw WorkspaceStorageError.missingRecord }
            guard task.state == .running else { return }
            executionVersion = task.metadata.version
            let version = task.metadata.version
            let skillRevision = task.skillRevisionId.flatMap { id in projection.skillRevisions.first { $0.metadata.id == id } }
            if let id = task.skillRevisionId {
                guard let skillRevision, skillRevision.metadata.id == id else { throw WorkspaceSkillError.revisionUnavailable }
                try WorkspaceSkillAccess.require(revision: skillRevision, agentID: configuration.agentId, configuration: configuration, projection: projection)
            }
            let checkpoint = try WorkspaceTaskCheckpoint(taskID: taskID, projection: projection)
            if !checkpoint.hasFinalResponse {
                let model = try await makeModel(configuration.modelId)
                let response = try await WorkspaceResponseRecorder(repository: repository, identity: identity)
                    .begin(id: UUID(), replyingTo: source, agentID: configuration.agentId)
                emit(response)
                let messages = try WorkspaceContextBuilder().messages(for: source, projection: projection, configuration: configuration)
                try await WorkspaceModelRuntime(repository: repository, identity: identity, pool: pool, tools: tools).generate(
                    source: source, responseID: response.metadata.id,
                    request: .init(messages: messages, maximumOutputTokens: maximumOutputTokens), model: model,
                    modelID: configuration.modelId, configuration: configuration, taskID: taskID, skillRevisionID: task.skillRevisionId,
                    budgetTokenLimit: task.budgetTokenLimit ?? 20_000, executionToolIDs: skillRevision.map { Set($0.toolIds) }, checkpoint: checkpoint,
                    validateExecution: {
                        guard let live = try await repository.record(BlotV3.Task.self, id: taskID, workspaceID: identity.workspaceID),
                              live.state == .running, live.metadata.version == version else { throw CancellationError() }
                        if live.executionMode == .delegated {
                            guard let authorize else { throw WorkspaceStorageError.permissionDenied }; try await authorize(live)
                        }
                        if let skillRevision {
                            let fresh = try await repository.projection(identity: identity)
                            guard let current = try WorkspaceAgentConfigurationResolver().resolve(agentID: configuration.agentId, projection: fresh) else { throw WorkspaceStorageError.missingRecord }
                            try WorkspaceSkillAccess.require(revision: skillRevision, agentID: configuration.agentId, configuration: current, projection: fresh)
                        }
                    }, emit: emit)
            }
            let after = try await repository.projection(identity: identity)
            let failed = try WorkspaceTaskCheckpoint(taskID: taskID, projection: after).hasFailedResults
            try await lifecycle.finish(taskID: taskID, state: failed ? .failed : .completed, expectedVersion: executionVersion)
        } catch {
            let state: BlotV3.TaskState = error is CancellationError || _Concurrency.Task.isCancelled || error as? WorkspaceTaskExecutionError == .uncertainToolResult ? .interrupted : .failed
            try? await lifecycle.finish(taskID: taskID, state: state, expectedVersion: executionVersion)
            throw error
        }
    }
}
