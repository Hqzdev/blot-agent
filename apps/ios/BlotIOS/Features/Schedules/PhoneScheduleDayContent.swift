import BlotDomain
import BlotWorkspace
import Foundation

struct PhoneScheduleDayContent {
    struct Run: Identifiable {
        let schedule: BlotV3.Automation
        let date: Date
        var id: UUID { schedule.metadata.id }
    }

    let runs: [Run]

    init(schedules: [BlotV3.Automation], day: Date, calendar: Calendar) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let calculator = WorkspaceScheduleCalculator()
        runs = schedules.compactMap { schedule in
            // Paused schedules remain visible on their scheduled day.
            let display = try? BlotV3.Automation(metadata: schedule.metadata, kind: schedule.kind,
                executorDeviceId: schedule.executorDeviceId, agentId: schedule.agentId,
                name: schedule.name, goal: schedule.goal, timezone: schedule.timezone,
                localTime: schedule.localTime, weekdays: schedule.weekdays,
                missedRunPolicy: schedule.missedRunPolicy, enabled: true,
                skillRevisionId: schedule.skillRevisionId, scheduledAt: schedule.scheduledAt,
                maxCatchUpRuns: schedule.maxCatchUpRuns)
            guard let display, let date = try? calculator.nextRun(for: display, after: start.addingTimeInterval(-0.001)),
                  date < end else { return nil }
            return Run(schedule: schedule, date: date)
        }.sorted { $0.date < $1.date }
    }
}
