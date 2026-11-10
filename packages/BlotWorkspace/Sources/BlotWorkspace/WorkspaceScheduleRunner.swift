import Foundation

public struct WorkspaceScheduleSweep: Sendable {
    public var taskIDs: [UUID] = []
    public var failedScheduleIDs: [UUID] = []
}

/// Runs only the explicitly assigned device's due schedules. Each fire is durable and idempotent.
public struct WorkspaceScheduleRunner: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    @discardableResult public func enqueueDueRuns(now: Date = Date()) async throws -> WorkspaceScheduleSweep {
        let projection = try await repository.projection(identity: identity)
        let calculator = WorkspaceScheduleCalculator()
        let service = WorkspaceScheduleService(repository: repository, identity: identity)
        var result = WorkspaceScheduleSweep()
        for schedule in projection.schedules where schedule.enabled && schedule.executorDeviceId == identity.deviceID {
            try _Concurrency.Task.checkCancellation()
            do {
                let latestRun = projection.automationRuns.filter { $0.automationId == schedule.metadata.id && $0.trigger != .manual }.map(\.scheduledAt).max()
                let saved = try await repository.scheduleWatermark(id: schedule.metadata.id, version: schedule.metadata.version)
                let watermark = max(saved ?? schedule.metadata.updatedAt, latestRun ?? schedule.metadata.updatedAt)
                for date in try calculator.dueRuns(for: schedule, after: watermark, through: now) {
                    try _Concurrency.Task.checkCancellation()
                    result.taskIDs.append(try await service.fire(scheduleID: schedule.metadata.id, scheduledAt: date,
                        expectedVersion: schedule.metadata.version, now: now))
                }
                try _Concurrency.Task.checkCancellation()
                try await repository.saveScheduleWatermark(id: schedule.metadata.id, version: schedule.metadata.version, through: now, identity: identity)
            } catch is CancellationError { throw CancellationError() }
            catch { result.failedScheduleIDs.append(schedule.metadata.id) }
        }
        return result
    }
}
