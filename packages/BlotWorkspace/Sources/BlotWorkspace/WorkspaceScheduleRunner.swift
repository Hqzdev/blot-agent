import Foundation

/// Runs only the explicitly assigned device's due schedules. Each fire is durable and idempotent.
public struct WorkspaceScheduleRunner: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func enqueueDueRuns(now: Date = Date()) async throws {
        let projection = try await repository.projection(identity: identity)
        let calculator = WorkspaceScheduleCalculator()
        let service = WorkspaceScheduleService(repository: repository, identity: identity)
        for schedule in projection.schedules where schedule.enabled && schedule.executorDeviceId == identity.deviceID {
            let watermark = projection.automationRuns.filter { $0.automationId == schedule.metadata.id && $0.trigger != .manual }
                .map(\.scheduledAt).max() ?? schedule.metadata.createdAt
            for date in try calculator.dueRuns(for: schedule, after: watermark, through: now) {
                _ = try await service.fire(scheduleID: schedule.metadata.id, scheduledAt: date, now: now)
            }
        }
    }
}
