import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func planCheckmarksStayOnOneMessageAndSurviveReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let url = directory.appendingPathComponent("db")
    let repository = try await workspaceTestRepository(url: url)
    let identity = try await repository.localIdentity()
    let service = WorkspaceAgentService(repository: repository, identity: identity)
    let first = try await service.save(commandID: UUID(), draft: .init(name: "CEO", instructions: "Coordinate"))
    let second = try await service.save(commandID: UUID(), draft: .init(name: "Analyst", instructions: "Analyze"))
    let group = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "Team", agentIDs: [first, second])
    let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: group, content: "Analyze together")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID))
    let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
    let id = UUID()
    _ = try await recorder.begin(id: id, replyingTo: source, agentID: first)
    let progress = WorkspaceGroupPlanProgress(summary: "Analysis", steps: [
        .init(agentID: first, name: "CEO", task: "Я проверю цель."),
        .init(agentID: second, name: "Analyst", task: "Я проанализирую данные.")
    ])
    let original = try await recorder.finish(id, delivery: .completed, content: progress.markdown)
    let changed = try await recorder.updateGroupPlan(id, progress: progress.updating(agentID: first, completed: true))
    #expect(changed.metadata.id == id && changed.position == original.position && changed.commandId == source.commandId)
    #expect(changed.metadata.version == original.metadata.version + 1)
    let decoded = try #require(WorkspaceGroupPlanProgress.decode(changed.content))
    #expect(decoded.completedCount == 1 && !decoded.allCompleted && decoded.steps[0].task == "Я проверю цель.")
    let invalid = WorkspaceGroupPlanProgress(summary: "Analysis", steps: [.init(agentID: first, name: "Another member", task: "Work"), progress.steps[1]])
    await #expect(throws: WorkspaceStorageError.permissionDenied) { try await recorder.updateGroupPlan(id, progress: invalid) }
    try await repository.close()
    let reopened = try WorkspaceRepository(url: url)
    let saved = try #require(try await reopened.record(BlotV3.Message.self, id: id, workspaceID: identity.workspaceID))
    #expect(WorkspaceGroupPlanProgress.decode(saved.content)?.completedCount == 1)
    try await reopened.close()
}

@Test func planParserKeepsMultilineDetailsAndDoesNotMistakeOrdinaryRepliesForPlans() {
    let plan = WorkspaceGroupPlanProgress(summary: "Line one\nLine two", steps: [
        .init(agentID: UUID(), name: "CEO", task: "Я проверю\nрезультат."),
        .init(agentID: UUID(), name: "Mail Manager", task: "Я создам черновик.", completed: true)
    ])
    let restored = WorkspaceGroupPlanProgress.decode(plan.markdown)
    #expect(restored?.steps.count == 2 && restored?.completedCount == 1)
    #expect(restored?.steps.first?.task == "Я проверю результат.")
    #expect(WorkspaceGroupPlanProgress.decode("CEO проверил результат.") == nil)
    #expect(WorkspaceGroupPlanProgress.decode("## Work plan\n\n- [x] @CEO — Done") == nil)
}

private actor StepVerificationModel: ChatModel {
    private(set) var calls = 0
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task {
                await self.countCall()
                continuation.yield(.text(#"{"summary":"Я всё сделал.","completed":true}"#))
                continuation.yield(.finished(.stop)); continuation.finish()
            }
        }
    }
    private func countCall() { calls += 1 }
}

@Test func aReplyOrDiscoveryCannotCompleteARequiredCreateOperation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db"))
    let identity = try await repository.localIdentity()
    let agents = WorkspaceAgentService(repository: repository, identity: identity)
    let id = try await agents.save(commandID: UUID(), draft: .init(name: "Agent", instructions: "Help"))
    let projection = try await repository.projection(identity: identity)
    let configuration = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: id, projection: projection))
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chats.createConversation(commandID: UUID(), title: "Test", agentID: id)
    let sourceID = try await chats.sendMessage(commandID: UUID(), conversationID: conversation, content: "Create a contact")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID))
    let responseID = UUID(), model = StepVerificationModel()
    _ = try await WorkspaceResponseRecorder(repository: repository, identity: identity).begin(id: responseID, replyingTo: source, agentID: id)
    let verifier = WorkspaceGroupStepVerifier(planner: .init(repository: repository, identity: identity, pool: .init()))
    let result = try await verifier.verify(source: source, responseID: responseID, task: "Create a contact", replies: ["Я создал контакт."],
        evidence: .init(steps: []), requiredTools: ["apple_contacts_create"], configuration: configuration, model: model, budgetTokenLimit: 20000)
    #expect(!result)
    #expect(await model.calls == 0)
    let steps = WorkspaceModelStepService(repository: repository, identity: identity)
    let discoveryID = UUID()
    let request = ChatModelRequest(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64)
    try await steps.begin(id: discoveryID, source: source, responseID: responseID, request: request, modelID: configuration.modelId,
        configurationID: configuration.metadata.id, budgetTokenLimit: 20000)
    try await steps.finish(id: discoveryID, state: .completed,
        calls: [.init(id: "discovery", name: "apple_contacts_resources", arguments: .object([:]))],
        results: ["discovery": .array([.object(["id": .string("contacts")])])], usage: nil)
    let discovered = WorkspaceGroupExecutionEvidence(steps: try await repository.projection(identity: identity).modelSteps)
    let stillPending = try await verifier.verify(source: source, responseID: responseID, task: "Create a contact", replies: ["Я создал контакт."],
        evidence: discovered, requiredTools: ["apple_contacts_create"], configuration: configuration, model: model, budgetTokenLimit: 20000)
    #expect(!stillPending && discovered.successfulTools == ["apple_contacts_resources"])
    #expect(await model.calls == 0)
    let createID = UUID()
    try await steps.begin(id: createID, source: source, responseID: responseID, request: request, modelID: configuration.modelId,
        configurationID: configuration.metadata.id, budgetTokenLimit: 20000)
    try await steps.finish(id: createID, state: .completed,
        calls: [.init(id: "create", name: "apple_contacts_create", arguments: .object([:]))],
        results: ["create": .object(["id": .string("new-contact")])], usage: nil)
    let finished = try await verifier.verify(source: source, responseID: responseID, task: "Create a contact", replies: ["Я создал контакт."],
        evidence: .init(steps: try await repository.projection(identity: identity).modelSteps), requiredTools: ["apple_contacts_create"],
        configuration: configuration, model: model, budgetTokenLimit: 20000)
    let verificationCalls = await model.calls
    #expect(finished && verificationCalls == 1)
    #expect(WorkspaceGroupExecutionEvidence.containsFailure(.object(["state": .string("unknown")])))
    #expect(WorkspaceGroupExecutionEvidence.containsFailure(.object(["error": .string("Denied")])))
    try await repository.close()
}
