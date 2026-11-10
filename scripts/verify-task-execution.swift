import BlotDomain
import BlotWorkspace
import Foundation

private actor ServiceTaskModel: ChatModel {
    private(set) var count = 0
    private var held = true
    func hold(_ value: Bool) { held = value }
    private func begin() { count += 1 }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                do {
                    await self.begin()
                    while await self.held { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
                    continuation.yield(.text("I completed the task.")); continuation.yield(.finished(.stop)); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}

@main struct VerifyTaskExecution {
    static func require(_ value: Bool, _ message: String = "Unexpected task state") { precondition(value, message) }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !condition(), ContinuousClock.now < deadline { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        require(try await condition(), "Timed out waiting for durable task state")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.sqlite")
        let repository = try WorkspaceRepository(url: url), identity = try await repository.localIdentity()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Worker", instructions: "Complete tasks", modelID: "gigachat"))
        let chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Tasks", agentID: agent)
        let model = ServiceTaskModel()
        let service = try LocalWorkspaceService(databaseURL: url, repository: repository, identity: identity,
            maximumOutputTokens: 64, makeModel: { _ in model })
        _ = try await service.load()
        var form = WorkspaceForm(); form.composer.draft = "Write one concise result"
        let request = WorkspaceRequest(action: .start, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil)
        _ = try await service.execute(request, snapshot: service.currentSnapshot())
        _ = try await service.execute(request, snapshot: service.currentSnapshot())
        try await wait { await model.count == 1 }
        let task = try await repository.projection(identity: identity).tasks.first!
        require(try await repository.projection(identity: identity).tasks.count == 1, "Repeated command created another task")
        _ = try await service.execute(.init(action: .pause, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: task.metadata.id), snapshot: service.currentSnapshot())
        require(try await repository.record(BlotV3.Task.self, id: task.metadata.id, workspaceID: identity.workspaceID)?.state == .paused)
        try await service.close()
        print("PASS: task creation, command replay and pause through LocalWorkspaceService")

        let reopened = try WorkspaceRepository(url: url)
        let resumed = try LocalWorkspaceService(databaseURL: url, repository: reopened, identity: identity, maximumOutputTokens: 64, makeModel: { _ in model })
        _ = try await resumed.load()
        require(try await reopened.projection(identity: identity).tasks.first?.state == .paused, "Reopening resumed a paused task")
        await model.hold(false)
        _ = try await resumed.execute(.init(action: .start, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: task.metadata.id), snapshot: resumed.currentSnapshot())
        try await wait { try await reopened.record(BlotV3.Task.self, id: task.metadata.id, workspaceID: identity.workspaceID)?.state == .completed }
        print("PASS: explicit resume after reopening completes the same task")

        await model.hold(true)
        _ = try await resumed.execute(.init(action: .start, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil), snapshot: resumed.currentSnapshot())
        try await wait { await model.count == 3 }
        let cancelID = try await reopened.projection(identity: identity).tasks.first { $0.metadata.id != task.metadata.id }!.metadata.id
        _ = try await resumed.execute(.init(action: .stop, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: cancelID), snapshot: resumed.currentSnapshot())
        require(try await reopened.record(BlotV3.Task.self, id: cancelID, workspaceID: identity.workspaceID)?.state == .canceled)
        print("PASS: stop cancels the worker and preserves canceled state")

        let sourceID = try await WorkspaceChatService(repository: reopened, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: "A regular chat reply")
        let source = try await reopened.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID)!
        let stream = try await resumed.responses(to: source)
        let consumer = _Concurrency.Task { for try await _ in stream { } }
        try await wait { await model.count == 4 }
        _ = try await resumed.execute(.init(action: .start, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil), snapshot: resumed.currentSnapshot())
        await model.hold(false)
        try await consumer.value
        try await wait {
            let projection = try await reopened.projection(identity: identity)
            return projection.tasks.count == 3 && projection.tasks.filter { $0.state == .completed }.count == 2
        }
        print("PASS: tasks wait for an active chat and start when its worker releases the conversation")
        await model.hold(true)
        _ = try await resumed.execute(.init(action: .start, form: form, selectedAgentID: agent, selectedConversationID: chat, selectedRecordID: nil), snapshot: resumed.currentSnapshot())
        try await wait { await model.count == 6 }
        let activeID = try await reopened.projection(identity: identity).tasks.first { $0.state == .running }!.metadata.id
        _ = try await resumed.cancelResponse(in: chat)
        require(try await reopened.record(BlotV3.Task.self, id: activeID, workspaceID: identity.workspaceID)?.state == .canceled)
        print("PASS: the chat stop action cancels its running task")
        try await resumed.close()
    }
}
