import BlotDomain
import BlotWorkspace
import Foundation

private actor ServiceSkillModel: ChatModel {
    let skillID: UUID
    private(set) var requests: [ChatModelRequest] = []
    init(skillID: UUID) { self.skillID = skillID }
    func events(_ request: ChatModelRequest) -> [ChatModelEvent] {
        requests.append(request)
        guard request.tools.contains(where: { $0.name == "skill_run" }) else { return [.text("Skill completed."), .finished(.stop)] }
        if !request.messages.contains(where: { $0.role == "tool" }) {
            return [.toolCall(.init(id: "list", name: "skill_list", arguments: .object([:]))), .finished(.toolCalls)]
        }
        if !request.messages.contains(where: { $0.toolCallID == "run" }) {
            return [.toolCall(.init(id: "run", name: "skill_run", arguments: .object(["skill_id": .string(skillID.uuidString), "values": .array([.object(["name": .string("topic"), "value": .string("Sales")])])]))), .finished(.toolCalls)]
        }
        return [.text("The skill is queued."), .finished(.stop)]
    }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task { for event in await self.events(request) { continuation.yield(event) }; continuation.finish() }
        }
    }
}

@main struct VerifySkillExecution {
    static func require(_ value: Bool, _ message: String) { precondition(value, message) }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(8))
        while try await !condition(), ContinuousClock.now < end { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        require(try await condition(), "Timed out")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("skills.sqlite")
        let repository = try WorkspaceRepository(url: url), identity = try await repository.localIdentity()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Worker", instructions: "Use the requested skill", modelID: "gigachat", toolIDs: ["document_create"]))
        let core = WorkspaceSkillService(repository: repository, identity: identity)
        let id = try await core.save(commandID: UUID(), name: "Brief", instructions: "Summarize {{topic}}", parameters: [.init(name: "topic")], toolIDs: [])
        let model = ServiceSkillModel(skillID: id)
        let service = try LocalWorkspaceService(databaseURL: url, repository: repository, identity: identity, maximumOutputTokens: 64, makeModel: { _ in model })
        _ = try await service.load()
        let skill = try await service.currentSnapshot().skills!.first!
        try await service.assignSkill(id, agentID: agent, assigned: true, version: 0)
        let first = try await service.runSkill(id, revisionID: skill.activeRevisionId, agentID: agent, values: ["topic": "Revenue"], conversationID: nil)
        try await wait { try await service.currentSnapshot().tasks?.first(where: { $0.metadata.id == first })?.state == .completed }
        let state = try await service.currentSnapshot()
        require(state.tasks?.first?.goal == "Summarize Revenue", "Skill parameters not saved")
        require(state.skillAssignments?.first?.assigned == true, "Assignment missing from snapshot")
        require(await model.requests.first?.tools.isEmpty == true, "Skill task gained unrelated tools")
        print("PASS: skill commands, assignment snapshot and restricted task queue execution")

        let chat = state.tasks!.first!.conversationId
        let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Run the Brief skill for Sales")
        let source = try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID)!
        for try await _ in try await service.responses(to: source) {}
        try await wait { try await service.currentSnapshot().tasks?.filter { $0.state == .completed }.count == 2 }
        let after = try await service.currentSnapshot()
        require(after.tasks?.contains(where: { $0.goal == "Summarize Sales" }) == true, "Model did not enqueue the skill")
        require(after.modelSteps?.contains(where: { $0.skillRevisionId == skill.activeRevisionId }) == true, "Execution lost skill provenance")
        print("PASS: model discovery, skill_run and separate completed skill task")

        try await service.archiveSkill(skill, archived: true)
        do {
            _ = try await service.runSkill(id, revisionID: skill.activeRevisionId, agentID: agent, values: ["topic": "Blocked"], conversationID: nil)
            preconditionFailure("Archived skill ran")
        } catch WorkspaceSkillError.archived {}
        require(try await service.currentSnapshot().tasks?.count == 2, "Failed run left a task")
        let nativeID = try await service.saveSkill(id: nil, version: 0, name: "Calendar reader", instructions: "Read events", parameters: [], tools: ["apple_calendar_list"])
        let nativeSnapshot = try await service.currentSnapshot()
        let nativeRevisionID = nativeSnapshot.skills!.first(where: { $0.metadata.id == nativeID })!.activeRevisionId
        require(nativeSnapshot.skillRevisions!.first(where: { $0.metadata.id == nativeRevisionID })!.toolIds == ["apple_calendar_list", "apple_calendar_resources"], "Native skill is missing resource discovery")
        print("PASS: native skill includes required resource discovery without granting agent permissions")
        await service.stopAll()
        let reopened = try LocalWorkspaceService(databaseURL: url, identity: identity, makeModel: { _ in model })
        let saved = try await reopened.load()!
        require(saved.skills?.first(where: { $0.metadata.id == id })?.archived == true && saved.skillAssignments?.first?.assigned == true, "Skill state lost on reopen")
        await reopened.stopAll()
        print("PASS: archive enforcement and durable skills after reopening service")
    }
}
