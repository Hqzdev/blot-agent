import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private func scheduleInstant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

private actor ScheduleClock: WorkspaceScheduleClock {
    private var instant: Date
    private var waiting: [UUID: (Date, CheckedContinuation<Void, Error>)] = [:]
    init(_ instant: Date) { self.instant = instant }
    func now() -> Date { instant }
    var sleepers: Int { waiting.count }
    func advance(to date: Date) {
        instant = date
        for (id, value) in waiting where value.0 <= date { waiting.removeValue(forKey: id)?.1.resume() }
    }
    func sleep(until date: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !_Concurrency.Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if date <= instant { continuation.resume() }
                else { waiting[id] = (date, continuation) }
            }
        } onCancel: { _Concurrency.Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) { waiting.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
}

private struct ScheduleFixture: Sendable {
    let directory: URL
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let agent: UUID
    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try await workspaceTestRepository(url: directory.appendingPathComponent("schedules.sqlite"))
        identity = try await repository.localIdentity()
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "Worker", instructions: "Complete the task"))
    }
    var service: WorkspaceScheduleService { .init(repository: repository, identity: identity) }
    var runner: WorkspaceScheduleRunner { .init(repository: repository, identity: identity) }
    func draft(at: Date? = nil, policy: BlotV3.MissedRunPolicy = .coalesce, enabled: Bool = true, executor: UUID? = nil) -> WorkspaceScheduleDraft {
        .init(name: "Digest", goal: "Write a short result", agentID: agent, executorDeviceID: executor ?? identity.deviceID,
            timezone: "UTC", localTime: "09:00", weekdays: [1, 2, 3, 4, 5, 6, 7], scheduledAt: at,
            missedRunPolicy: policy, maximumCatchUpRuns: 3, enabled: enabled)
    }
    func runs() async throws -> [BlotV3.AutomationRun] { try await repository.records(BlotV3.AutomationRun.self, workspaceID: identity.workspaceID) }
}

private func waitForSchedule(_ condition: @Sendable () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while try await !condition(), ContinuousClock.now < deadline { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
    #expect(try await condition())
}

@Test func scheduleEngineRunsAtTheDeadlineWithoutAnyViewOrPollingCaller() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-06T08:00:00Z"), due = start.addingTimeInterval(10)
    let id = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(at: due), now: start)
    let clock = ScheduleClock(start), engine = WorkspaceScheduleEngine(repository: fixture.repository, identity: fixture.identity, clock: clock)
    await engine.start()
    try await waitForSchedule { await clock.sleepers > 0 }
    #expect(try await fixture.runs().isEmpty)
    await clock.advance(to: due)
    try await waitForSchedule { try await fixture.runs().count == 1 }
    await engine.wake(); await engine.wake()
    _ = try await engine.checkNow()
    #expect(try await fixture.runs().count == 1)
    #expect(try await fixture.runs().first?.automationId == id)
    await engine.stop()
    #expect(await clock.sleepers == 0)
}

@Test func scheduleEngineObservesEditsAndDisablingWithoutChangingScreens() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-06T08:00:00Z"), clock = ScheduleClock(start)
    let engine = WorkspaceScheduleEngine(repository: fixture.repository, identity: fixture.identity, clock: clock)
    await engine.start()
    try await waitForSchedule { await clock.sleepers > 0 }
    let first = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(at: start.addingTimeInterval(10)), now: start)
    _ = try await engine.checkNow()
    let old = try #require(try await fixture.repository.record(BlotV3.Automation.self, id: first, workspaceID: fixture.identity.workspaceID))
    _ = try await fixture.service.save(commandID: UUID(), scheduleID: first, expectedVersion: old.metadata.version,
        draft: fixture.draft(at: start.addingTimeInterval(10), enabled: false), now: start.addingTimeInterval(1))
    await clock.advance(to: start.addingTimeInterval(10))
    _ = try await engine.checkNow()
    #expect(try await fixture.runs().isEmpty)
    let second = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(at: start.addingTimeInterval(15)), now: start.addingTimeInterval(10))
    _ = try await engine.checkNow()
    await clock.advance(to: start.addingTimeInterval(15))
    try await waitForSchedule { try await fixture.runs().contains { $0.automationId == second } }
    #expect(try await fixture.runs().count == 1)
    await engine.stop()
}

@Test(arguments: [BlotV3.MissedRunPolicy.coalesce, .catch_up, .skip])
func scheduleMissedRunPolicySurvivesRestartAndRepeatedChecks(_ policy: BlotV3.MissedRunPolicy) async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-01T00:00:00Z"), now = scheduleInstant("2026-11-06T12:00:00Z")
    let id = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(policy: policy), now: start)
    _ = try await fixture.runner.enqueueDueRuns(now: now)
    let expected = policy == .skip ? 0 : policy == .catch_up ? 3 : 1
    #expect(try await fixture.runs().count == expected)
    let reopened = try await workspaceTestRepository(url: fixture.directory.appendingPathComponent("schedules.sqlite"))
    _ = try await WorkspaceScheduleRunner(repository: reopened, identity: fixture.identity).enqueueDueRuns(now: now.addingTimeInterval(10))
    #expect(try await fixture.runs().count == expected)
    #expect(try await reopened.scheduleWatermark(id: id, version: 1) == now.addingTimeInterval(10))
    // Moving the clock backwards cannot lower the durable watermark or replay an occurrence.
    _ = try await fixture.runner.enqueueDueRuns(now: now.addingTimeInterval(-3600))
    #expect(try await reopened.scheduleWatermark(id: id, version: 1) == now.addingTimeInterval(10))
    _ = try await fixture.runner.enqueueDueRuns(now: scheduleInstant("2026-11-07T09:00:00Z"))
    #expect(try await fixture.runs().count == expected + 1)
}

@Test func scheduleConcurrentChecksAndRestoredReplicasNeverDuplicateAnOccurrence() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-06T08:00:00Z"), due = start.addingTimeInterval(10)
    let id = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(at: due), now: start)
    async let a = fixture.runner.enqueueDueRuns(now: due)
    async let b = fixture.runner.enqueueDueRuns(now: due)
    _ = try await (a, b)
    let runs = try await fixture.runs()
    #expect(runs.count == 1)
    let taskID = try #require(runs.first?.execution.taskId)
    let restored = try await workspaceTestRepository(url: fixture.directory.appendingPathComponent("replica.sqlite"))
    let restoredIdentity = try await restored.accountIdentity(ownerID: fixture.identity.ownerID, workspaceID: fixture.identity.workspaceID)
    try await restored.installReplicaSnapshot(fixture.repository.replicaSnapshot(identity: fixture.identity), identity: restoredIdentity)
    let replay = try await WorkspaceScheduleService(repository: restored, identity: restoredIdentity).fire(scheduleID: id, scheduledAt: due, now: due)
    #expect(replay == taskID)
    #expect(try await restored.records(BlotV3.AutomationRun.self, workspaceID: fixture.identity.workspaceID).count == 1)
}

@Test func scheduleManualRunDoesNotConsumeAutomaticOccurrenceAndRemoteSchedulesStayRemote() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-06T08:00:00Z"), due = scheduleInstant("2026-11-06T09:00:00Z")
    let id = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(), now: start)
    _ = try await fixture.service.runManually(commandID: UUID(), scheduleID: id, now: due.addingTimeInterval(-30))
    _ = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(executor: UUID()), now: start)
    let result = try await fixture.runner.enqueueDueRuns(now: due)
    #expect(result.taskIDs.count == 1 && result.failedScheduleIDs.isEmpty)
    #expect(try await fixture.runs().count == 2)
    #expect(try await fixture.runs().filter { $0.trigger == .scheduled }.count == 1)
}

@Test func scheduleEnableStartsFromTheNewRevisionAndStaleChecksCannotFireOldGoals() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-01T00:00:00Z"), enabledAt = scheduleInstant("2026-11-06T12:00:00Z")
    let id = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(enabled: false), now: start)
    _ = try await fixture.service.save(commandID: UUID(), scheduleID: id, expectedVersion: 1, draft: fixture.draft(), now: enabledAt)
    let result = try await fixture.runner.enqueueDueRuns(now: enabledAt)
    #expect(result.taskIDs.isEmpty && result.failedScheduleIDs.isEmpty)
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        _ = try await fixture.service.fire(scheduleID: id, scheduledAt: scheduleInstant("2026-11-07T09:00:00Z"), expectedVersion: 1, now: scheduleInstant("2026-11-07T09:00:00Z"))
    }
    _ = try await fixture.runner.enqueueDueRuns(now: scheduleInstant("2026-11-07T09:00:00Z"))
    #expect(try await fixture.runs().count == 1)
}

@Test func scheduleInvalidConfigurationDoesNotBlockHealthySchedulesAndCanRecover() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-06T08:00:00Z"), now = scheduleInstant("2026-11-06T12:00:00Z")
    let invalid = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(), now: start)
    _ = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(), now: start)
    _ = try await fixture.repository.execute(commandID: UUID(), command: Data("test-invalid-schedule".utf8), identity: fixture.identity) { tx in
        let old = try tx.require(BlotV3.Automation.self, id: invalid)
        let changed = try BlotV3.Automation(metadata: tx.metadata(id: invalid, now: start, replacing: old.metadata), kind: old.kind,
            executorDeviceId: old.executorDeviceId, agentId: old.agentId, name: old.name, goal: old.goal, timezone: "Invalid/Zone",
            localTime: old.localTime, weekdays: old.weekdays, missedRunPolicy: old.missedRunPolicy, enabled: true)
        try tx.put(changed, expectedVersion: old.metadata.version)
        return invalid
    }
    let engine = WorkspaceScheduleEngine(repository: fixture.repository, identity: fixture.identity, clock: ScheduleClock(now))
    await engine.start()
    _ = try await engine.checkNow()
    #expect(try await fixture.repository.scheduleFailures() == [invalid])
    #expect(try await fixture.runs().count == 1)
    _ = try await fixture.service.save(commandID: UUID(), scheduleID: invalid, expectedVersion: 2, draft: fixture.draft(), now: start)
    _ = try await engine.checkNow()
    #expect(try await fixture.repository.scheduleFailures().isEmpty)
    #expect(try await fixture.runs().count == 2)
    await engine.stop()
}

@Test func scheduleStopCancelsTheTimerAndReopeningCatchesUpOnce() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    let start = scheduleInstant("2026-11-06T08:00:00Z"), due = start.addingTimeInterval(10), clock = ScheduleClock(start)
    _ = try await fixture.service.save(commandID: UUID(), draft: fixture.draft(at: due), now: start)
    let engine = WorkspaceScheduleEngine(repository: fixture.repository, identity: fixture.identity, clock: clock)
    await engine.start()
    try await waitForSchedule { await clock.sleepers > 0 }
    await engine.stop()
    await clock.advance(to: due.addingTimeInterval(3600))
    #expect(try await fixture.runs().isEmpty)
    await engine.start()
    try await waitForSchedule { try await fixture.runs().count == 1 }
    await engine.stop()
}

@Test func scheduleRejectsMalformedTimeAndDoesNotRunTwiceInTheRepeatedDSTHour() async throws {
    let fixture = try await ScheduleFixture(); defer { cleanupWorkspaceTestStorage(fixture.directory) }
    var draft = fixture.draft()
    for time in ["oops:09:30", "09::30", "24:00", "09:60"] {
        draft.localTime = time
        await #expect(throws: WorkspaceStorageError.invalidParameters) { _ = try await fixture.service.save(commandID: UUID(), draft: draft) }
    }
    draft.localTime = "01:30"; draft.timezone = "America/New_York"; draft.weekdays = [7]; draft.missedRunPolicy = .catch_up
    _ = try await fixture.service.save(commandID: UUID(), draft: draft, now: scheduleInstant("2026-10-31T00:00:00Z"))
    _ = try await fixture.runner.enqueueDueRuns(now: scheduleInstant("2026-11-01T05:45:00Z"))
    _ = try await fixture.runner.enqueueDueRuns(now: scheduleInstant("2026-11-01T06:45:00Z"))
    #expect(try await fixture.runs().count == 1)
    #expect(try await fixture.runs().first?.scheduledAt == scheduleInstant("2026-11-01T05:30:00Z"))
    let stored = try #require(try await fixture.repository.records(BlotV3.Automation.self, workspaceID: fixture.identity.workspaceID).first)
    #expect(try WorkspaceScheduleCalculator().nextRun(for: stored, after: scheduleInstant("2026-11-01T05:45:00Z")) == scheduleInstant("2026-11-08T06:30:00Z"))
}
