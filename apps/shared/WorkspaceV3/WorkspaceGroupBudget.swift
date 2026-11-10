import BlotDomain
import BlotWorkspace
import Foundation

/// Uses durable model steps to bound the entire round and each individual model loop.
@MainActor
struct WorkspaceGroupBudget {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let sourceID: UUID
    private let baseline: Set<UUID>
    private var totalLimit: Int
    private let perTurnLimit: Int
    private var configurationID: UUID? = nil

    init(repository: WorkspaceRepository, identity: WorkspaceIdentity, sourceID: UUID,
         projection: WorkspaceProjection, perTurnLimit: Int, phases: Int) throws {
        let (total, overflow) = perTurnLimit.multipliedReportingOverflow(by: phases)
        guard !overflow, perTurnLimit > 0, phases > 0 else { throw WorkspaceGroupResponseError.budgetExceeded }
        self.repository = repository; self.identity = identity; self.sourceID = sourceID
        baseline = Set(projection.modelSteps.map(\.metadata.id))
        totalLimit = total; self.perTurnLimit = perTurnLimit
    }

    func remaining() async throws -> Int {
        min(perTurnLimit, try await availableTotal())
    }
    func scoped(configurationID: UUID, baseline: WorkspaceProjection, limit: Int) throws -> Self {
        var scope = try Self(repository: repository, identity: identity, sourceID: sourceID, projection: baseline, perTurnLimit: perTurnLimit, phases: 1)
        guard limit > 0 else { throw WorkspaceGroupResponseError.budgetExceeded }
        scope.totalLimit = limit
        scope.configurationID = configurationID
        return scope
    }
    func availableTotal() async throws -> Int {
        let projection = try await repository.projection(identity: identity)
        var used = 0
        for step in projection.modelSteps where step.sourceMessageId == sourceID && !baseline.contains(step.metadata.id) && (configurationID == nil || step.configurationId == configurationID) {
            let cost: Int
            if let input = step.inputTokens, let output = step.outputTokens {
                let boundedInput = min(input, totalLimit)
                cost = boundedInput + min(output, totalLimit - boundedInput)
            } else {
                let request = try JSONDecoder().decode(ChatModelRequest.self, from: Data(step.requestJSON.utf8))
                cost = step.requestJSON.utf8.count + request.maximumOutputTokens
            }
            used += min(cost, totalLimit - used)
        }
        guard used < totalLimit else { throw WorkspaceGroupResponseError.budgetExceeded }
        return totalLimit - used
    }
}
