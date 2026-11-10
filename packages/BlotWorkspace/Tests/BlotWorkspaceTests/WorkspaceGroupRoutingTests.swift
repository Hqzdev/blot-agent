import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func socialMessagesSkipPlanningButGreetingsWithWorkDoNot() {
    for text in ["Привет!", "Всем привет 👋", "Как у вас дела?", "Hello, how are you?"] { #expect(WorkspaceGroupDecision.isCasual(text)) }
    for text in ["Привет, создай встречу завтра", "Как дела с отчётом?", "Hi, analyze this file", "Спасибо, теперь отправь письмо"] { #expect(!WorkspaceGroupDecision.isCasual(text)) }
}
@Test func routingSelectsOneSpecialistOrOnlyRelevantTeamMembers() throws {
    let ids = [UUID(), UUID(), UUID()]
    let members = Set(ids)
    #expect(try WorkspaceGroupDecision.decode("{\"mode\":\"specialist\",\"agentID\":\"\(ids[1])\"}", members: members).agentID == ids[1])
    let team = "{\"mode\":\"team\",\"summary\":\"Analyze, then make a table\",\"assignments\":[{\"agentID\":\"\(ids[1])\",\"task\":\"Analyze\"},{\"agentID\":\"\(ids[2])\",\"task\":\"Table\"}]}"
    #expect(try WorkspaceGroupDecision.decode(team, members: members).assignments?.count == 2)
    for bad in [team.replacingOccurrences(of: ids[2].uuidString, with: ids[1].uuidString), team.replacingOccurrences(of: ids[2].uuidString, with: UUID().uuidString), "{\"mode\":\"team\",\"assignments\":[]}", "hello", "}{"] {
        #expect(throws: (any Error).self) { _ = try WorkspaceGroupDecision.decode(bad, members: members) }
    }
    #expect(throws: (any Error).self) { _ = try WorkspaceGroupDecision.decode(team, members: [ids[1]]) }
}
@Test func groupPinsAndMessageRepliesAreDurableAndOnlyCoordinatorPlansCanBePinned() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db"))
    defer { cleanupWorkspaceTestStorage(directory) }
    let identity = try await repository.localIdentity()
    let service = WorkspaceAgentService(repository: repository, identity: identity)
    let ceo = try await service.save(commandID: UUID(), draft: .init(name: "CEO", instructions: "Coordinate"))
    let analyst = try await service.save(commandID: UUID(), draft: .init(name: "Data Analyst", instructions: "Analyze"))
    let group = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "Team", agentIDs: [ceo, analyst])
    let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: group, content: "Analyze and make a table")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID))
    let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
    let plan = try await recorder.begin(id: UUID(), replyingTo: source, agentID: ceo)
    _ = try await recorder.finish(plan.metadata.id, delivery: .completed, content: "@Data Analyst — analyze")
    _ = try await recorder.relate(plan.metadata.id, replyTo: sourceID)
    try await repository.pinGroupPlan(messageID: plan.metadata.id, identity: identity)
    #expect(try await repository.pinnedGroupPlans()[group] == plan.metadata.id)
    let reply = try await recorder.begin(id: UUID(), replyingTo: source, agentID: analyst)
    _ = try await recorder.finish(reply.metadata.id, delivery: .completed, content: "👋 @CEO, analysis is ready")
    let linked = try await recorder.relate(reply.metadata.id, replyTo: plan.metadata.id)
    #expect(linked.replyToMessageId == plan.metadata.id && linked.mentions?.first?.agentId == ceo)
    let mention = try #require(linked.mentions?.first)
    #expect((linked.content as NSString).substring(with: .init(location: mention.startUTF16, length: mention.lengthUTF16)) == "@CEO")
    await #expect(throws: WorkspaceStorageError.permissionDenied) { try await repository.pinGroupPlan(messageID: reply.metadata.id, identity: identity) }
    try await repository.unpinGroupPlan(conversationID: group, messageID: UUID())
    #expect(try await repository.pinnedGroupPlans()[group] == plan.metadata.id)
    try await repository.unpinGroupPlan(conversationID: group, messageID: plan.metadata.id)
    #expect(try await repository.pinnedGroupPlans().isEmpty)
}

private actor GroupToolProbe: WorkspaceToolExecuting {
    nonisolated var definitions: [ChatToolDefinition] { [.init(name: "probe", description: "Probe", parameters: .object(["type": .string("object"), "properties": .object([:])]))] }
    var calls = 0
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON { calls += 1; return .object([:]) }
}
private actor GroupReplyProbe: ChatModel {
    var requests: [ChatModelRequest] = []
    private func record(_ request: ChatModelRequest) { requests.append(request) }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task { await record(request); continuation.yield(.text("Hello")); continuation.yield(.finished(.stop)); continuation.finish() }
        }
    }
}
@Test func toolFreeConversationNeverExposesToolsEvenWhenTheAgentHasGrants() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db"))
    defer { cleanupWorkspaceTestStorage(directory) }
    let identity = try await repository.localIdentity()
    let id = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Agent", instructions: "Help", toolIDs: ["probe"]))
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Hello", agentID: id)
    let sourceID = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Hello")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID))
    let projection = try await repository.projection(identity: identity)
    let configuration = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: id, projection: projection))
    let tool = GroupToolProbe(), model = GroupReplyProbe()
    let responseID = UUID()
    _ = try await WorkspaceResponseRecorder(repository: repository, identity: identity).begin(id: responseID, replyingTo: source, agentID: id)
    try await WorkspaceModelRuntime(repository: repository, identity: identity, pool: .init(), tools: .init(providers: [tool])).generate(
        source: source, responseID: responseID, request: .init(messages: [.init(role: "user", content: "Hello")], maximumOutputTokens: 256),
        model: model, modelID: "test", configuration: configuration, budgetTokenLimit: 20000, toolsEnabled: false, emit: { _ in })
    #expect(await model.requests.count == 1)
    #expect(await model.requests.first?.tools.isEmpty == true)
    #expect(await tool.calls == 0)
}
