import BlotDomain
import BlotWorkspace
import Foundation

private actor ParallelGroupModel: ChatModel {
    let ids: [UUID]
    let scenario: String
    private(set) var active = 0
    private(set) var maximum = 0
    private(set) var workerBStarted = false
    private(set) var workerBAfterVerification = false
    private var verifiedA = false
    init(_ ids: [UUID], scenario: String) { self.ids = ids; self.scenario = scenario }
    func events(_ request: ChatModelRequest) async throws -> [ChatModelEvent] {
        let system = request.messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        let text: String
        if system.contains("Select the interaction mode") {
            let depends = ["dependency", "blockedDependency"].contains(scenario) ? ",\"dependsOn\":[\"\(ids[1])\"]" : ""
            text = "{\"mode\":\"team\",\"summary\":\"Checks\",\"assignments\":[{\"agentID\":\"\(ids[1])\",\"task\":\"Report A\"},{\"agentID\":\"\(ids[2])\",\"task\":\"Report B\"\(depends)}]}"
        } else if system.contains("Rewrite each assigned task") {
            text = "{\"summary\":\"Checks\",\"assignments\":[{\"agentID\":\"\(ids[1])\",\"task\":\"I will report A.\"},{\"agentID\":\"\(ids[2])\",\"task\":\"I will report B.\"}]}"
        } else if system.contains("Verify completion of one assigned step") {
            if request.messages.last?.content.contains("Assignment: Report A") == true { verifiedA = true }
            text = "{\"summary\":\"I completed my check.\",\"completed\":true}"
        } else if system.contains("working in this group as yourself") {
            let isB = system.contains("You are B, working")
            if isB { workerBStarted = true; workerBAfterVerification = verifiedA }
            active += 1; maximum = max(maximum, active)
            defer { active -= 1 }
            try await _Concurrency.Task.sleep(for: scenario == "cancel" ? .seconds(5) : .milliseconds(150))
            if !isB && ["failure", "blockedDependency"].contains(scenario) { return [.failure(.http(503))] }
            text = isB ? "B-done" : "A-done"
        } else {
            text = "{\"summary\":\"The verified checks are reported.\",\"completed\":\(["failure", "blockedDependency"].contains(scenario) ? "false" : "true")}"
        }
        return [.text(text), .finished(.stop)]
    }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = _Concurrency.Task {
                do { for event in try await self.events(request) { continuation.yield(event) }; continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
@main struct VerifyParallelGroups {
    static func require(_ value: Bool, _ message: String = "Unexpected group state") { precondition(value, message) }
    @MainActor static func main() async throws {
        for scenario in ["parallel", "dependency", "failure", "blockedDependency", "cancel"] { try await verify(scenario) }
    }
    @MainActor private static func verify(_ scenario: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try WorkspaceRepository(url: directory.appendingPathComponent("group.sqlite")), identity = try await repository.localIdentity()
        var ids: [UUID] = []
        for name in ["Coordinator", "A", "B"] {
            ids.append(try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: name, instructions: "Report one result", modelID: "gigachat")))
        }
        let chat = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "Parallel checks", agentIDs: ids)
        let id = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Run two separate checks and report the results")
        let source = try await repository.record(BlotV3.Message.self, id: id, workspaceID: identity.workspaceID)!
        let model = ParallelGroupModel(ids, scenario: scenario)
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("group.sqlite"), repository: repository, identity: identity, maximumOutputTokens: 128, makeModel: { _ in model })
        _ = try await service.load()
        let stream = try await service.responses(to: source)
        if scenario == "cancel" {
            let consumer = _Concurrency.Task { for try await _ in stream {} }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while await model.active < 2, ContinuousClock.now < deadline { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
            require(await model.active == 2, "Both workers must start before canceling")
            _ = try await service.cancelResponse(in: chat)
            _ = await consumer.result
            require(try await repository.projection(identity: identity).messages.allSatisfy { $0.delivery != .running })
        } else {
            for try await _ in stream {}
            let projection = try await repository.projection(identity: identity)
            let progress = projection.messages.compactMap { WorkspaceGroupPlanProgress.decode($0.content) }.first!
            if scenario == "parallel" { require(await model.maximum == 2, "Independent workers did not overlap"); require(progress.allCompleted) }
            if scenario == "dependency" { let maximum = await model.maximum; let afterVerification = await model.workerBAfterVerification; require(maximum == 1 && afterVerification, "Dependent worker started before verification"); require(progress.allCompleted) }
            if scenario == "failure" { require(await model.maximum == 2); require(progress.completedCount == 1 && !progress.allCompleted) }
            if scenario == "blockedDependency" { require(await !model.workerBStarted); require(!progress.allCompleted) }
        }
        try await service.close()
        print("PASS: group", scenario)
    }
}
