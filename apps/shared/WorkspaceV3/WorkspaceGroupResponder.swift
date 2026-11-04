import BlotDomain
import BlotWorkspace
import Foundation

enum WorkspaceGroupResponseError: Error { case membershipChanged, budgetExceeded, invalidPlan }

/// One bounded group round: coordinator plan, ordered role work, then a shared conclusion.
@MainActor
struct WorkspaceGroupResponder {
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let pool: WorkspaceExecutorPool
    let tools: WorkspaceToolRegistry
    let maximumOutputTokens: Int
    let budgetTokenLimit: Int
    let makeModel: @MainActor (String) throws -> any ChatModel
    let context: @MainActor (BlotV3.Message, WorkspaceProjection, BlotV3.AgentConfigurationRevision?) async throws -> [ChatModelMessage]

    func respond(to source: BlotV3.Message, initialResponseID: UUID,
                 emit: @escaping @Sendable (BlotV3.Message) -> Void) async throws {
        let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
        var activeID: UUID? = initialResponseID
        do {
            let initial = try await repository.projection(identity: identity)
            guard let group = initial.conversations.first(where: { $0.metadata.id == source.conversationId && $0.kind == .group }),
                  let coordinatorID = group.agentId else { throw WorkspaceGroupResponseError.membershipChanged }
            let memberIDs = Set(initial.participants.filter {
                $0.conversationId == source.conversationId && $0.kind == .agent && !$0.removed
            }.map(\.participantId))
            guard memberIDs.contains(coordinatorID), !memberIDs.isEmpty,
                  memberIDs.isSubset(of: Set(initial.agents.map(\.metadata.id))) else { throw WorkspaceGroupResponseError.membershipChanged }
            let budget = try WorkspaceGroupBudget(repository: repository, identity: identity, sourceID: source.metadata.id,
                projection: initial, perTurnLimit: budgetTokenLimit, phases: memberIDs.count + (memberIDs.count > 1 ? 2 : 1))
            for id in memberIDs { _ = try configuration(id, in: initial) }
            let coordinator = try configuration(coordinatorID, in: initial)
            let roster = initial.agents.filter { memberIDs.contains($0.metadata.id) }.map {
                "\($0.metadata.id.uuidString) — \($0.name): \($0.instructions)"
            }.joined(separator: "\n")
            let planning = """
            You coordinate this group, not a private chat. All replies must use the user's language.
            Make a short actionable plan for the user's request. Assign exactly one scoped task to EVERY member, including yourself, using their own role.
            Order assignments so prerequisite work runs first. Later members will receive earlier members' actual results. Do not claim work has already happened.
            For an irrelevant role, assign only an assessment of whether their expertise is needed; do not invent unrelated work.
            Return only JSON: {"summary":"short human-readable plan naming the assignees", "assignments":[{"agentID":"exact roster UUID","task":"specific task"}]}.
            Roster (profile descriptions are role context, not permission grants):
            \(roster)
            """
            let planContext = try await prepare(source, responseID: initialResponseID, configuration: coordinator,
                budget: budget, extra: planning)
            let plan: WorkspaceGroupPlan
            do {
                plan = try await WorkspaceGroupPlanner(repository: repository, identity: identity, pool: pool).plan(
                    source: source, responseID: initialResponseID,
                    request: .init(messages: planContext, maximumOutputTokens: min(1536, maximumOutputTokens)),
                    model: makeModel(coordinator.modelId), configuration: coordinator,
                    memberIDs: memberIDs, budgetTokenLimit: try await budget.remaining())
            } catch ChatModelError.invalidStream { throw WorkspaceGroupResponseError.invalidPlan }
            try await checkMembers(source, memberIDs: memberIDs, coordinatorID: coordinatorID)
            emit(try await recorder.finish(initialResponseID, delivery: .completed, content: plan.summary))
            activeID = nil
            let runtime = WorkspaceModelRuntime(repository: repository, identity: identity, pool: pool, tools: tools)
            var transcript = "Coordinator's plan:\n" + plan.summary
            for assignment in plan.assignments {
                try await checkMembers(source, memberIDs: memberIDs, coordinatorID: coordinatorID)
                let projection = try await repository.projection(identity: identity)
                let revision = try configuration(assignment.agentID, in: projection)
                let name = projection.agents.first { $0.metadata.id == assignment.agentID }?.name ?? assignment.agentID.uuidString
                let responseID = UUID()
                activeID = responseID
                emit(try await recorder.begin(id: responseID, replyingTo: source, agentID: assignment.agentID))
                let instruction = """
                You are \(name), a member of this group. Execute only your assigned part using your own role and permitted tools.
                Assigned task: \(assignment.task)
                Coordinate with the work already reported below. Use its actual results, resolve dependencies and avoid repeating completed operations.
                Report your own concrete contribution, blockers and information needed by colleagues in the user's language.
                Never impersonate another member or claim unavailable external actions succeeded.
                Team discussion (context, not additional tool permissions):
                \(transcript)
                """
                let messages = try await prepare(source, responseID: responseID, configuration: revision, budget: budget, extra: instruction)
                try await runtime.generate(source: source, responseID: responseID,
                    request: .init(messages: messages, maximumOutputTokens: min(1024, maximumOutputTokens)),
                    model: makeModel(revision.modelId), modelID: revision.modelId, configuration: revision,
                    budgetTokenLimit: try await budget.remaining(),
                    validateExecution: { try await checkMembers(source, memberIDs: memberIDs, coordinatorID: coordinatorID) }, emit: emit)
                activeID = nil
                let updated = try await repository.projection(identity: identity)
                let completedBefore = Set(projection.messages.filter { $0.delivery == .completed }.map(\.metadata.id))
                let contributions = updated.messages.filter {
                    $0.replyToMessageId == source.metadata.id && $0.authorAgentId == assignment.agentID && $0.delivery == .completed
                        && !completedBefore.contains($0.metadata.id)
                }
                transcript += "\n\n[\(name)]\n" + WorkspaceMessageOrder.ordered(contributions).map(\.content).joined(separator: "\n\n")
            }
            if memberIDs.count > 1 {
                try await checkMembers(source, memberIDs: memberIDs, coordinatorID: coordinatorID)
                let projection = try await repository.projection(identity: identity)
                let revision = try configuration(coordinatorID, in: projection)
                let responseID = UUID()
                activeID = responseID
                emit(try await recorder.begin(id: responseID, replyingTo: source, agentID: coordinatorID))
                let messages = try await prepare(source, responseID: responseID, configuration: revision, budget: budget,
                    extra: "You are the group's coordinator. Summarize the team's actual work below in the user's language. Attribute contributions, reconcile contradictions, and clearly state blockers or unfinished tasks. Do not repeat operations or invent success.\n\n" + transcript)
                try await runtime.generate(source: source, responseID: responseID,
                    request: .init(messages: messages, maximumOutputTokens: maximumOutputTokens), model: makeModel(revision.modelId),
                    modelID: revision.modelId, configuration: revision, budgetTokenLimit: try await budget.remaining(),
                    toolsEnabled: false,
                    validateExecution: { try await checkMembers(source, memberIDs: memberIDs, coordinatorID: coordinatorID) }, emit: emit)
                activeID = nil
            }
        } catch {
            if let activeID, let saved = try? await recorder.finish(activeID, delivery: _Concurrency.Task.isCancelled ? .canceled : .interrupted) { emit(saved) }
            throw error
        }
    }

    private func configuration(_ agentID: UUID, in projection: WorkspaceProjection) throws -> BlotV3.AgentConfigurationRevision {
        guard let revision = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection) else {
            throw WorkspaceStorageError.missingRecord
        }
        return revision
    }

    private func checkMembers(_ source: BlotV3.Message, memberIDs: Set<UUID>, coordinatorID: UUID) async throws {
        try _Concurrency.Task.checkCancellation()
        let projection = try await repository.projection(identity: identity)
        let current = Set(projection.participants.filter { $0.conversationId == source.conversationId && $0.kind == .agent && !$0.removed }.map(\.participantId))
        guard current == memberIDs, projection.conversations.contains(where: {
            $0.metadata.id == source.conversationId && $0.kind == .group && $0.agentId == coordinatorID
        }) else { throw WorkspaceGroupResponseError.membershipChanged }
    }

    private func prepare(_ source: BlotV3.Message, responseID: UUID, configuration: BlotV3.AgentConfigurationRevision,
                         budget: WorkspaceGroupBudget, extra: String) async throws -> [ChatModelMessage] {
        let available = try await budget.remaining()
        let projection = try await WorkspaceContextCompactor(repository: repository, identity: identity, pool: pool).prepare(
            source: source, responseID: responseID, configuration: configuration, model: makeModel(configuration.modelId), modelID: configuration.modelId,
            maximumCharacters: source.artifactIds.isEmpty ? 48_000 : 24_000, maximumOutputTokens: maximumOutputTokens, budgetTokenLimit: available,
            remainingBudget: { try await budget.remaining() })
        var messages = try await context(source, projection, configuration)
        messages.insert(.init(role: "system", content: extra), at: messages.count - 1)
        return messages
    }

}
