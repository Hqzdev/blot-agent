import BlotDomain
import Foundation

/// A recorded, tool-free planning turn. JSON is validated before its human summary is published.
public struct WorkspaceGroupPlanner: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let pool: WorkspaceExecutorPool
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, pool: WorkspaceExecutorPool) {
        self.repository = repository; self.identity = identity; self.pool = pool
    }

    public func plan(source: BlotV3.Message, responseID: UUID, request: ChatModelRequest,
                     model: any ChatModel, configuration: BlotV3.AgentConfigurationRevision,
                     memberIDs: Set<UUID>, budgetTokenLimit: Int) async throws -> WorkspaceGroupPlan {
        try WorkspaceGroupPlan.decode(await text(source: source, responseID: responseID, request: request,
            model: model, configuration: configuration, budgetTokenLimit: budgetTokenLimit), memberIDs: memberIDs)
    }

    public func text(source: BlotV3.Message, responseID: UUID, request: ChatModelRequest,
                     model: any ChatModel, configuration: BlotV3.AgentConfigurationRevision,
                     budgetTokenLimit: Int) async throws -> String {
        guard request.tools.isEmpty, try JSONEncoder().encode(request).count + request.maximumOutputTokens <= budgetTokenLimit else {
            throw WorkspaceStorageError.permissionDenied
        }
        let steps = WorkspaceModelStepService(repository: repository, identity: identity)
        let stepID = UUID()
        try await steps.begin(id: stepID, source: source, responseID: responseID, request: request,
            modelID: configuration.modelId, configurationID: configuration.metadata.id, stepIndex: 0, budgetTokenLimit: budgetTokenLimit)
        var usage: ChatModelUsage?
        do {
            try await pool.acquire()
            var text = ""
            var finished = false
            do {
                for try await event in model.stream(request: request) {
                    try _Concurrency.Task.checkCancellation()
                    switch event {
                    case .text(let delta):
                        guard !finished else { throw ChatModelError.invalidStream }
                        text += delta
                    case .usage(let value): usage = value
                    case .finished(let reason):
                        guard !finished, reason == .stop else { throw ChatModelError.interrupted }
                        finished = true
                    case .toolCall: throw ChatModelError.invalidStream
                    case .failure(let error): throw error
                    }
                }
                await pool.release()
            } catch { await pool.release(); throw error }
            guard finished else { throw ChatModelError.interrupted }
            try await steps.finish(id: stepID, state: .completed, usage: usage)
            return text
        } catch {
            try? await steps.finish(id: stepID, state: _Concurrency.Task.isCancelled ? .canceled : .interrupted, usage: usage)
            throw error
        }
    }
}
