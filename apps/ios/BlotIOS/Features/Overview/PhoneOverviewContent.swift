import BlotDomain
import BlotWorkspace
import Foundation

struct PhoneOverviewContent {
    struct Upcoming: Identifiable {
        let schedule: BlotV3.Automation
        let date: Date
        var id: UUID { schedule.metadata.id }
    }

    let attention: [BlotV3.Task]
    let active: [BlotV3.Task]
    let completed: [BlotV3.Task]
    let upcoming: [Upcoming]
    let files: [BlotV3.Artifact]

    init(snapshot: WorkspaceSnapshot, now: Date) {
        let tasks = (snapshot.tasks ?? []).sorted { $0.metadata.updatedAt > $1.metadata.updatedAt }
        let attentionStates: Set<BlotV3.TaskState> = [.waiting_approval, .waiting_user, .interrupted, .failed]
        attention = tasks.filter { attentionStates.contains($0.state) }
        active = tasks.filter { [.planning, .queued, .running, .paused, .draft].contains($0.state) }
        completed = Array(tasks.filter { $0.state == .completed }.prefix(3))
        let calculator = WorkspaceScheduleCalculator()
        upcoming = Array(snapshot.schedules.compactMap { schedule in
            guard let date = try? calculator.nextRun(for: schedule, after: now) else { return nil }
            return Upcoming(schedule: schedule, date: date)
        }.sorted { $0.date < $1.date }.prefix(3))
        files = Array(snapshot.artifacts.sorted { $0.metadata.updatedAt > $1.metadata.updatedAt }.prefix(3))
    }
}
