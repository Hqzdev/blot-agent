import BlotDomain
import BlotWidgetSupport
import BlotWorkspace
import Foundation
import OSLog
import WidgetKit

@MainActor
final class PhoneWidgetPublisher {
    private let storage = WidgetSnapshotStore()
    private let log = Logger(subsystem: "dev.blot.widgets", category: "Snapshot")
    private var pending: _Concurrency.Task<Void, Never>?
    private var rendering: _Concurrency.Task<Void, Never>?

    private var latest: (snapshot: WorkspaceSnapshot, language: String)?

    func update(_ snapshot: WorkspaceSnapshot, language: String, immediately: Bool = false) {
        latest = (snapshot, language)
        if immediately || snapshot.ownerID == nil {
            pending?.cancel(); pending = nil
            publishLatest()
            return
        }
        guard pending == nil else { return }
        pending = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(for: .seconds(1)) } catch { return }
            self?.pending = nil
            self?.publishLatest()
        }
    }

    private func publishLatest() {
        guard let source = latest else { return }
        latest = nil
        rendering?.cancel()
        rendering = _Concurrency.Task { [weak self] in
            let value = await _Concurrency.Task.detached(priority: .utility) {
                Self.project(source.snapshot, language: source.language)
            }.value
            guard !_Concurrency.Task.isCancelled else { return }
            self?.write(value)
        }
    }

    private nonisolated static func project(_ snapshot: WorkspaceSnapshot, language: String) -> WidgetSnapshot {
        let now = Date()
        let calculator = WorkspaceScheduleCalculator()
        let schedules = snapshot.schedules.compactMap { schedule -> WidgetSchedule? in
            guard schedule.metadata.ownerId == snapshot.ownerID,
                  let date = try? calculator.nextRun(for: schedule, after: now) else { return nil }
            return .init(id: schedule.metadata.id, title: String(schedule.name.prefix(100)), agentID: schedule.agentId, nextRun: date)
        }
        return WidgetSnapshotProjector().project(ownerID: snapshot.ownerID, agents: snapshot.agents,
            conversations: snapshot.conversations, messages: snapshot.messages, tasks: snapshot.tasks ?? [],
            actions: snapshot.preparedActions ?? [], schedules: schedules, language: language, now: now)
    }

    private func write(_ value: WidgetSnapshot) {
        do {
            if try storage.write(value) { WidgetCenter.shared.reloadAllTimelines() }
        } catch { log.error("Could not publish the widget snapshot") }
    }
}
