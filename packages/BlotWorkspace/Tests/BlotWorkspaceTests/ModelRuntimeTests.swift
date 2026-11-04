import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor ToolCounter: WorkspaceToolExecuting {
    nonisolated let definitions = [ChatToolDefinition(name: "record_value", description: "Record a value", parameters:
        .object(["type": .string("object"), "properties": .object(["value": .object(["type": .string("string")])]),
                 "required": .array([.string("value")])]))]
    private(set) var count = 0
    func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        count += 1
        return .object(["saved": .bool(true)])
    }
}
private actor LoopModel: ChatModel {
    private(set) var requests: [ChatModelRequest] = []
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                let number = await record(request)
                if number == 1 {
                    continuation.yield(.toolCall(.init(id: "one", name: "record_value", arguments: .object(["value": .string("saved")]))))
                    continuation.yield(.usage(try! .init(inputTokens: 10, outputTokens: 5)))
                    continuation.yield(.finished(.toolCalls))
                } else {
                    continuation.yield(.text("Result"))
                    continuation.yield(.usage(try! .init(inputTokens: 20, outputTokens: 8)))
                    continuation.yield(.finished(.stop))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
    private func record(_ request: ChatModelRequest) -> Int { requests.append(request); return requests.count }
}

@Test func typedToolLoopPersistsRequestsCallsResultsAndUsageBeforeNextTurn() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db.sqlite"))
    let identity = try await repository.localIdentity()
    let agentID = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
        draft: .init(name: "Agent", instructions: "Use the tool", modelID: "gigachat", toolIDs: ["record_value"]))
    let projection = try await repository.projection(identity: identity)
    let configuration = try #require(projection.configurations.first)
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversationID = try await chat.createConversation(commandID: UUID(), title: "Test", agentID: agentID)
    let messageID = try await chat.sendMessage(commandID: UUID(), conversationID: conversationID, content: "Use the tool")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: messageID, workspaceID: identity.workspaceID))
    let responseID = UUID()
    _ = try await WorkspaceResponseRecorder(repository: repository, identity: identity).begin(id: responseID, replyingTo: source, agentID: agentID)
    let counter = ToolCounter(), model = LoopModel()
    let runtime = WorkspaceModelRuntime(repository: repository, identity: identity, pool: .init(), tools: try .init(providers: [counter]))
    try await runtime.generate(source: source, responseID: responseID, request: .init(messages: [.init(role: "user", content: source.content)], maximumOutputTokens: 64),
        model: model, modelID: "gigachat", configuration: configuration, budgetTokenLimit: 10000, emit: { _ in })
    #expect(await counter.count == 1)
    let requests = await model.requests
    #expect(requests.count == 2)
    #expect(requests[1].messages.last?.role == "tool")
    let saved = try await repository.projection(identity: identity)
    #expect(saved.modelSteps.count == 2)
    #expect(saved.modelSteps.allSatisfy { $0.state == .completed })
    #expect(saved.modelSteps.reduce(0) { $0 + ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0) } == 43)
    #expect(saved.modelSteps.first { $0.stepIndex == 0 }?.toolResultsJSON?.contains("saved") == true)
    let firstStep = try #require(saved.modelSteps.first { $0.stepIndex == 0 })
    try await WorkspaceModelStepService(repository: repository, identity: identity).finish(id: firstStep.metadata.id,
        state: .completed, calls: [.init(id: "one", name: "record_value", arguments: .object(["value": .string("saved")]))],
        results: ["one": .object(["saved": .bool(true)])], usage: .init(inputTokens: 10, outputTokens: 5))
    #expect(try await repository.record(BlotV3.ModelStep.self, id: firstStep.metadata.id, workspaceID: identity.workspaceID)?.metadata.version == firstStep.metadata.version)
    #expect(saved.messages.first { $0.metadata.id == responseID }?.content == "Result")
    #expect(saved.messages.first { $0.metadata.id == responseID }?.delivery == .completed)
}

@Test func toolValidationRejectsUnknownFieldsAndTypesBeforeExecution() async throws {
    let counter = ToolCounter()
    let registry = try WorkspaceToolRegistry(providers: [counter])
    for fields: [String: ChatJSON] in [["value": .number(4)], ["value": .string("ok"), "extra": .bool(true)], [:]] {
        await #expect(throws: WorkspaceToolError.invalidArguments) {
            _ = try await registry.execute(.init(id: "id", name: "record_value", arguments: .object(fields)),
                context: .init(sourceMessageID: UUID(), taskID: nil, allowedToolIDs: ["record_value"]))
        }
    }
    #expect(await counter.count == 0)
}

@Test func processLockRejectsAnotherOwnerAndReleasesOnClose() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var first: WorkspaceProcessLock? = try .init(directory: directory)
    #expect(first != nil)
    #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try WorkspaceProcessLock(directory: directory) }
    first = nil
    _ = try WorkspaceProcessLock(directory: directory)
}
