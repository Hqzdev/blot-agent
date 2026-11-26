import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct PlanningTools: WorkspaceToolExecuting {
    var definitions: [ChatToolDefinition] {
        ["inspect", "save_report"].map { .init(name: $0, description: $0, parameters: .object(["type": .string("object"), "properties": .object([:])])) }
    }
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        Issue.record("Planning must never execute workspace tools")
        throw WorkspaceToolError.invalidArguments
    }
}
private struct PlanningModel: ChatModel {
    let agent: UUID
    var invalid = false
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { stream in
            stream.yield(.toolCall(.init(id: "plan", name: request.requiredTool!, arguments: .object([
                "mode": .string("specialist"), "agentID": .string(agent.uuidString), "firstToolID": .string("inspect"),
                "toolSteps": .array([
                    .object(["toolID": .string("inspect"), "instruction": .string("Read the requested input")]),
                    .object(["toolID": .string(invalid ? "unauthorized_send" : "save_report"), "instruction": .string("Save the report from the real previous result")])])]))))
            if let usage = try? ChatModelUsage(inputTokens: 100, outputTokens: 50) { stream.yield(.usage(usage)) }
            stream.yield(.finished(.toolCalls)); stream.finish()
        }
    }
}

@Test func directWorkPlanRecordsEveryStepAndRejectsUnavailableTools() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
        draft: .init(name: "Planner", instructions: "Help", toolIDs: ["inspect", "save_report"]))
    let configuration = try #require(try await repository.projection(identity: identity).configurations.first)
    let chats = WorkspaceChatService(repository: repository, identity: identity)
    let chat = try await chats.createConversation(commandID: UUID(), title: "Plan", agentID: agent)
    let id = try await chats.sendMessage(commandID: UUID(), conversationID: chat, content: "1. Read the input. 2. Save the report.")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: id, workspaceID: identity.workspaceID))
    let response = UUID(), recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
    _ = try await recorder.begin(id: response, replyingTo: source, agentID: agent)
    let planner = WorkspaceDirectWorkPlanner(repository: repository, identity: identity, pool: .init())
    let tools = try WorkspaceToolRegistry(providers: [PlanningTools()])
    let plan = try await planner.plan(source: source, responseID: response, configuration: configuration,
        context: [.init(role: "user", content: source.content)], tools: tools, model: PlanningModel(agent: agent), maximumOutputTokens: 1000, budget: 20000)
    #expect(plan.operations.map(\.toolID) == ["inspect", "save_report"])
    #expect(plan.remainingBudget == 19850)
    let snapshot = try await repository.projection(identity: identity)
    #expect(snapshot.modelSteps.count == 1 && snapshot.invocations.isEmpty && snapshot.actions.isEmpty)
    #expect(snapshot.messages.first { $0.metadata.id == response }?.delivery == .running)
    await #expect(throws: ChatModelError.invalidStream) {
        try await planner.plan(source: source, responseID: response, configuration: configuration,
            context: [], tools: tools, model: PlanningModel(agent: agent, invalid: true), maximumOutputTokens: 1000, budget: 20000)
    }
}

@Test func workPlanningDoesNotAddARoutingTurnToSimpleChat() {
    #expect(!WorkspaceDirectWorkPlanner.isMultiStep("Hello"))
    #expect(!WorkspaceDirectWorkPlanner.isMultiStep("Создай PDF"))
    #expect(!WorkspaceDirectWorkPlanner.isMultiStep("Как сначала workspace_read_file, затем workspace_write_file?"))
    #expect(WorkspaceDirectWorkPlanner.isMultiStep("1) Прочитай бюджет. 2) Сохрани отчёт."))
    #expect(WorkspaceDirectWorkPlanner.isMultiStep("Сначала workspace_read_file, затем workspace_write_file и workspace_create_directory."))
}
