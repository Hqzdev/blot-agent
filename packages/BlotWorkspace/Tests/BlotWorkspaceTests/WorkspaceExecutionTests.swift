import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct ExecutionWorkspace {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var url: URL { directory.appendingPathComponent("workspace.sqlite") }
    func clean() { cleanupWorkspaceTestStorage(directory) }
}

private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

@Test func taskPinsConfigurationLimitsDepthAndCancellationReachesChildren() async throws {
    let files = ExecutionWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let agents = WorkspaceAgentService(repository: repository, identity: identity)
    let agent = try await agents.save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Original"))
    let conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Tasks", agentID: agent)
    let tasks = WorkspaceTaskService(repository: repository, identity: identity)
    let root = try await tasks.create(commandID: UUID(), conversationID: conversation, agentID: agent, goal: "Root", executorDeviceID: identity.deviceID)
    let original = try #require(try await repository.record(BlotV3.Task.self, id: root, workspaceID: identity.workspaceID))
    _ = try await agents.save(commandID: UUID(), agentID: agent, expectedVersion: 1, draft: .init(name: "Worker", instructions: "Changed"))
    let child = try await tasks.create(commandID: UUID(), conversationID: conversation, agentID: agent, goal: "Child", executorDeviceID: identity.deviceID, parentTaskID: root)
    let grandchild = try await tasks.create(commandID: UUID(), conversationID: conversation, agentID: agent, goal: "Grandchild", executorDeviceID: identity.deviceID, parentTaskID: child)
    await #expect(throws: WorkspaceStorageError.invalidParameters) {
        _ = try await tasks.create(commandID: UUID(), conversationID: conversation, agentID: agent, goal: "Too deep", executorDeviceID: identity.deviceID, parentTaskID: grandchild)
    }
    let configurationID = try #require(original.configurationId)
    let pinned = try #require(try await repository.record(BlotV3.AgentConfigurationRevision.self, id: configurationID, workspaceID: identity.workspaceID))
    #expect(pinned.instructions == "Original")
    try await tasks.cancel(commandID: UUID(), taskID: root)
    let projection = try await repository.projection(identity: identity)
    #expect(projection.tasks.count == 3 && projection.tasks.allSatisfy { $0.state == .canceled })
    #expect(projection.sessions.count == 3 && projection.sessions.allSatisfy { $0.state == .canceled })
}

@Test func childBudgetCannotRaiseRootCapAndActualUsageIsSettledOnce() async throws {
    let files = ExecutionWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Work"))
    let conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Budget", agentID: agent)
    let tasks = WorkspaceTaskService(repository: repository, identity: identity)
    let root = try await tasks.create(commandID: UUID(), conversationID: conversation, agentID: agent, goal: "Root", executorDeviceID: identity.deviceID, budgetTokenLimit: 100)
    let child = try await tasks.create(commandID: UUID(), conversationID: conversation, agentID: agent, goal: "Child", executorDeviceID: identity.deviceID, parentTaskID: root)
    let budget = WorkspaceBudgetService(repository: repository, identity: identity)
    let request = UUID()
    _ = try await budget.reserve(requestID: request, taskID: child, tokens: 80, limit: 10_000)
    _ = try await budget.reserve(requestID: request, taskID: child, tokens: 80, limit: 10_000)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await budget.reserve(requestID: UUID(), taskID: root, tokens: 30, limit: 10_000) }
    try await budget.settle(commandID: UUID(), requestID: request, actualTokens: 20)
    try await budget.settle(commandID: UUID(), requestID: request, actualTokens: 20)
    _ = try await budget.reserve(requestID: UUID(), taskID: root, tokens: 70, limit: 10_000)
    let ledger = try await repository.records(BlotV3.BudgetLedger.self, workspaceID: identity.workspaceID)
    #expect(ledger.count == 2)
    #expect(ledger.first { $0.requestId == request }?.actualTokens == 20)
}

@Test func schedulesHandleDSTAndBoundedMissedRuns() throws {
    let metadata = try BlotV3.RecordMetadata(id: UUID(), ownerId: UUID(), workspaceId: UUID(), version: 1,
        createdAt: instant("2026-01-01T00:00:00Z"), updatedAt: instant("2026-01-01T00:00:00Z"))
    func schedule(time: String, timezone: String, weekdays: [Int], policy: BlotV3.MissedRunPolicy = .coalesce) throws -> BlotV3.Automation {
        try .init(metadata: metadata, kind: .task, executorDeviceId: UUID(), agentId: UUID(), name: "Schedule", goal: "Work",
            timezone: timezone, localTime: time, weekdays: weekdays, missedRunPolicy: policy, enabled: true, maxCatchUpRuns: 2)
    }
    let calculator = WorkspaceScheduleCalculator()
    #expect(try calculator.nextRun(for: schedule(time: "02:30", timezone: "America/New_York", weekdays: [7]), after: instant("2026-03-08T00:00:00Z")) == instant("2026-03-08T07:00:00Z"))
    #expect(try calculator.nextRun(for: schedule(time: "01:30", timezone: "America/New_York", weekdays: [7]), after: instant("2026-11-01T00:00:00Z")) == instant("2026-11-01T05:30:00Z"))
    let allDays = [1, 2, 3, 4, 5, 6, 7]
    let watermark = instant("2026-11-01T00:00:00Z"); let now = instant("2026-11-04T12:00:00Z")
    #expect(try calculator.dueRuns(for: schedule(time: "08:00", timezone: "UTC", weekdays: allDays), after: watermark, through: now) == [instant("2026-11-04T08:00:00Z")])
    #expect(try calculator.dueRuns(for: schedule(time: "08:00", timezone: "UTC", weekdays: allDays, policy: .catch_up), after: watermark, through: now) == [instant("2026-11-03T08:00:00Z"), instant("2026-11-04T08:00:00Z")])
    #expect(try calculator.dueRuns(for: schedule(time: "08:00", timezone: "UTC", weekdays: allDays, policy: .skip), after: watermark, through: now).isEmpty)
}

@Test func repeatedScheduleFireSurvivesReopeningAndNeverTransfersExecutor() async throws {
    let files = ExecutionWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Work"))
    let schedules = WorkspaceScheduleService(repository: repository, identity: identity)
    let date = instant("2026-11-03T09:00:00Z")
    let id = try await schedules.save(commandID: UUID(), draft: .init(name: "Digest", goal: "Summarize", agentID: agent,
        executorDeviceID: identity.deviceID, timezone: "UTC", localTime: "09:00", weekdays: [], scheduledAt: date), now: date.addingTimeInterval(-60))
    let task = try await schedules.fire(scheduleID: id, scheduledAt: date, now: date)
    let reopened = try await workspaceTestRepository(url: files.url)
    #expect(try await WorkspaceScheduleService(repository: reopened, identity: identity).fire(scheduleID: id, scheduledAt: date, now: date.addingTimeInterval(60)) == task)
    #expect(try await reopened.records(BlotV3.AutomationRun.self, workspaceID: identity.workspaceID).count == 1)
    #expect(try await reopened.records(BlotV3.Task.self, workspaceID: identity.workspaceID).count == 1)
    let otherDevice = UUID()
    let remote = try await schedules.save(commandID: UUID(), draft: .init(name: "Remote", goal: "Wait", agentID: agent,
        executorDeviceID: otherDevice, timezone: "UTC", localTime: "09:00", weekdays: [], scheduledAt: date), now: date.addingTimeInterval(-60))
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await schedules.fire(scheduleID: remote, scheduledAt: date, now: date) }
    let manual = try await schedules.runManually(commandID: UUID(), scheduleID: remote, now: date)
    #expect(try await reopened.record(BlotV3.Task.self, id: manual, workspaceID: identity.workspaceID)?.execution.executorDeviceId == otherDevice)
}
