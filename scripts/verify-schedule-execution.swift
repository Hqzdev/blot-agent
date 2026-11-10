import BlotDomain
import BlotWorkspace
import Foundation

private actor ScheduleServiceClock: WorkspaceScheduleClock {
    private var date: Date
    private var waits: [UUID: (Date, CheckedContinuation<Void, Error>)] = [:]
    init(_ date: Date) { self.date = date }
    func now() -> Date { date }
    func waitsFor(_ target: Date) -> Bool { waits.values.contains { $0.0 == target } }
    func advance(to date: Date) {
        self.date = date
        for (id, value) in waits where value.0 <= date { waits.removeValue(forKey: id)?.1.resume() }
    }
    func sleep(until target: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if _Concurrency.Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if target <= date { continuation.resume() }
                else { waits[id] = (target, continuation) }
            }
        } onCancel: { _Concurrency.Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) { waits.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
}

private actor ScheduleServiceModel: ChatModel {
    private(set) var count = 0
    private func called() { count += 1 }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task {
                await self.called()
                continuation.yield(.text("I completed the scheduled task."))
                continuation.yield(.usage(try! .init(inputTokens: 10, outputTokens: 5)))
                continuation.yield(.finished(.stop)); continuation.finish()
            }
        }
    }
}

@main struct VerifyScheduleExecution {
    static func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func require(_ value: Bool, _ message: String = "Unexpected schedule state") { precondition(value, message) }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !condition(), ContinuousClock.now < deadline { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        require(try await condition(), "Timed out waiting for scheduled work")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.sqlite")
        let repository = try WorkspaceRepository(url: url), identity = try await repository.localIdentity()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Complete tasks", modelID: "gigachat"))
        let start = instant("2026-11-06T08:00:00Z"), clock = ScheduleServiceClock(start), model = ScheduleServiceModel()
        let service = try LocalWorkspaceService(databaseURL: url, repository: repository, identity: identity,
            maximumOutputTokens: 64, scheduleClock: clock, makeModel: { _ in model })
        _ = try await service.load()
        var form = WorkspaceForm()
        form.schedule.name = "One-time"; form.schedule.goal = "Write a concise result"
        form.schedule.agentID = agent; form.schedule.deviceID = identity.deviceID; form.schedule.timezone = "UTC"
        form.schedule.oneTime = true; form.schedule.time = start.addingTimeInterval(10)
        _ = try await service.execute(.init(action: .createSchedule, form: form, selectedAgentID: agent, selectedConversationID: nil, selectedRecordID: nil), snapshot: service.currentSnapshot())
        try await wait { await clock.waitsFor(start.addingTimeInterval(10)) }
        await clock.advance(to: start.addingTimeInterval(10))
        try await wait { try await repository.projection(identity: identity).automationRuns.filter { $0.state == .completed }.count == 1 }
        require(await model.count == 1)
        print("PASS: time-based launch executes through LocalWorkspaceService without a view")

        form.schedule.name = "Recurring"; form.schedule.oneTime = false; form.schedule.time = instant("2026-11-06T09:00:00Z")
        form.schedule.weekdays = [1, 2, 3, 4, 5, 6, 7]; form.schedule.missedRunPolicy = .catch_up; form.schedule.maximumCatchUpRuns = 2
        let saved = try await service.execute(.init(action: .createSchedule, form: form, selectedAgentID: agent, selectedConversationID: nil, selectedRecordID: nil), snapshot: service.currentSnapshot())
        let recurringID = saved.schedules.first { $0.name == "Recurring" }!.metadata.id
        await clock.advance(to: instant("2026-11-09T12:00:00Z"))
        _ = try await service.enqueueDueSchedules()
        try await wait { try await repository.projection(identity: identity).automationRuns.filter { $0.state == .completed }.count == 3 }
        require(await model.count == 3)
        print("PASS: a sleep/clock gap creates only the configured two catch-up executions")

        _ = try await service.runScheduleManually(recurringID)
        try await wait { try await repository.projection(identity: identity).automationRuns.filter { $0.state == .completed }.count == 4 }
        _ = try await service.enqueueDueSchedules()
        let manual = try await repository.projection(identity: identity).automationRuns.filter { $0.trigger == .manual }
        require(manual.count == 1)
        _ = try await service.execute(.init(action: .updateSchedule, form: form, selectedAgentID: agent, selectedConversationID: nil, selectedRecordID: recurringID), snapshot: service.currentSnapshot())
        await clock.advance(to: instant("2026-11-10T10:00:00Z"))
        _ = try await service.enqueueDueSchedules()
        require(await model.count == 4)
        _ = try await service.execute(.init(action: .updateSchedule, form: form, selectedAgentID: agent, selectedConversationID: nil, selectedRecordID: recurringID), snapshot: service.currentSnapshot())
        _ = try await service.enqueueDueSchedules()
        require(await model.count == 4, "Re-enabling executed disabled intervals")
        await clock.advance(to: instant("2026-11-11T09:00:00Z"))
        _ = try await service.enqueueDueSchedules()
        try await wait { try await repository.projection(identity: identity).automationRuns.filter { $0.state == .completed }.count == 5 }
        print("PASS: manual runs, disable and re-enable preserve the automatic timeline")
        try await service.close()

        await clock.advance(to: instant("2026-11-13T12:00:00Z"))
        require(await model.count == 5, "Closed service executed scheduled work")
        let reopened = try WorkspaceRepository(url: url)
        let restored = try LocalWorkspaceService(databaseURL: url, repository: reopened, identity: identity,
            maximumOutputTokens: 64, scheduleClock: clock, makeModel: { _ in model })
        _ = try await restored.load()
        try await wait { try await reopened.projection(identity: identity).automationRuns.filter { $0.state == .completed }.count == 7 }
        _ = try await restored.enqueueDueSchedules()
        require(await model.count == 7)
        let snapshot = try await restored.currentSnapshot()
        require(snapshot.automationRuns?.count == 7 && snapshot.scheduleFailures?.isEmpty == true)
        print("PASS: reopening catches up once and publishes actual run results")
        try await restored.close()
    }
}
