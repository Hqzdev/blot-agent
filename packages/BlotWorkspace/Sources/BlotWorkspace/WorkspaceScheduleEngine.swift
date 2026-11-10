import BlotDomain
import Foundation

/// An account-owned wall-clock scheduler. UI visibility does not own its timer or work.
public actor WorkspaceScheduleEngine {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let clock: any WorkspaceScheduleClock
    private let onActivity: @Sendable (Bool) async -> Void
    private var observer: _Concurrency.Task<Void, Never>?
    private var loop: _Concurrency.Task<Void, Never>?
    private var sleeper: _Concurrency.Task<Void, Error>?
    private var sweep: _Concurrency.Task<WorkspaceScheduleSweep, Error>?
    private var versions: [UUID: Int]?
    private var generation = 0
    private var stopped = true

    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity,
                clock: any WorkspaceScheduleClock = WorkspaceSystemScheduleClock(),
                onActivity: @escaping @Sendable (Bool) async -> Void = { _ in }) {
        self.repository = repository; self.identity = identity; self.clock = clock; self.onActivity = onActivity
    }
    public func start() async {
        guard stopped else { return }
        stopped = false
        let changes = await repository.changes()
        observer = _Concurrency.Task { [weak self] in
            for await _ in changes {
                guard !_Concurrency.Task.isCancelled else { return }
                await self?.schedulesChanged()
            }
        }
        loop = _Concurrency.Task { [weak self] in await self?.run() }
    }
    public func wake() {
        guard !stopped else { return }
        generation += 1
        sleeper?.cancel()
    }
    @discardableResult public func checkNow() async throws -> WorkspaceScheduleSweep {
        guard !stopped else { throw CancellationError() }
        if let sweep { return try await sweep.value }
        let pending = _Concurrency.Task { [repository, identity, clock] in
            let now = await clock.now()
            let result = try await WorkspaceScheduleRunner(repository: repository, identity: identity).enqueueDueRuns(now: now)
            try _Concurrency.Task.checkCancellation()
            try await repository.saveScheduleFailures(result.failedScheduleIDs)
            return result
        }
        sweep = pending
        defer { sweep = nil }
        let result = try await pending.value
        guard !stopped else { throw CancellationError() }
        let schedules = try await repository.records(BlotV3.Automation.self, workspaceID: identity.workspaceID)
        let runs = try await repository.records(BlotV3.AutomationRun.self, workspaceID: identity.workspaceID)
        let now = await clock.now()
        let active = schedules.contains { schedule in
            guard schedule.enabled, schedule.executorDeviceId == identity.deviceID else { return false }
            guard let date = schedule.scheduledAt else { return true }
            return !runs.contains { $0.automationId == schedule.metadata.id && $0.trigger != .manual && $0.scheduledAt == date }
                && (schedule.missedRunPolicy != .skip || now.timeIntervalSince(date) <= 60)
        }
        guard !stopped else { throw CancellationError() }
        await onActivity(active)
        return result
    }
    public func stop() async {
        stopped = true
        observer?.cancel(); observer = nil
        sleeper?.cancel(); sweep?.cancel(); loop?.cancel()
        let currentLoop = loop, currentSweep = sweep
        await currentLoop?.value; _ = await currentSweep?.result
        loop = nil; sleeper = nil; sweep = nil
        await onActivity(false)
    }
    private func schedulesChanged() async {
        guard !stopped, let schedules = try? await repository.records(BlotV3.Automation.self, workspaceID: identity.workspaceID) else { return }
        let updated = Dictionary(uniqueKeysWithValues: schedules.map { ($0.metadata.id, $0.metadata.version) })
        guard versions != updated else { return }
        versions = updated; wake()
    }
    private func run() async {
        while !stopped && !_Concurrency.Task.isCancelled {
            let scanned = generation
            do { try await checkNow() }
            catch is CancellationError { if stopped || _Concurrency.Task.isCancelled { return } }
            catch { /* Storage/network-independent state will be checked again at the bounded interval. */ }
            guard !stopped, !_Concurrency.Task.isCancelled else { return }
            let now = await clock.now()
            var next = now.addingTimeInterval(30)
            if let schedules = try? await repository.records(BlotV3.Automation.self, workspaceID: identity.workspaceID) {
                for schedule in schedules where schedule.enabled && schedule.executorDeviceId == identity.deviceID {
                    if let date = try? WorkspaceScheduleCalculator().nextRun(for: schedule, after: now) { next = min(next, date) }
                }
            }
            if generation != scanned { continue }
            let waiting = _Concurrency.Task { [clock, next] in try await clock.sleep(until: next) }
            sleeper = waiting
            _ = await waiting.result
            sleeper = nil
        }
    }
}
