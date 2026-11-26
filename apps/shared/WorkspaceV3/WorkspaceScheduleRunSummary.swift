import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceScheduleRunSummary: View {
    let schedule: BlotV3.Automation
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    private var latest: BlotV3.AutomationRun? {
        (store.snapshot.automationRuns ?? []).filter { $0.automationId == schedule.metadata.id }
            .max { $0.metadata.createdAt < $1.metadata.createdAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let next = try? WorkspaceScheduleCalculator().nextRun(for: schedule, after: context.date) {
                    HStack(spacing: 5) {
                        Text(store.language == "ru" ? "Следующий запуск:" : "Next run:")
                        Text(next, format: .dateTime.day().month().hour().minute())
                    }.environment(\.timeZone, TimeZone(identifier: schedule.timezone) ?? .current)
                }
            }
            if let run = latest {
                HStack(spacing: 5) {
                    Text(store.language == "ru" ? "Последний запуск:" : "Last run:")
                    WorkspaceTaskStateLabel(state: run.state)
                    Text(run.scheduledAt, format: .dateTime.day().month().hour().minute())
                }.environment(\.timeZone, TimeZone(identifier: schedule.timezone) ?? .current)
                if let task = (store.snapshot.tasks ?? []).first(where: { $0.metadata.id == run.execution.taskId }) {
                    Button(store.t("Task details")) {
                        if let panelNavigation {
                            panelNavigation.taskID = task.metadata.id
                            panelNavigation.open(.running)
                        } else {
                            store.openConversation(task.conversationId)
                            store.selectedRecordID = task.metadata.id
                            store.navigate(.running)
                        }
                    }.buttonStyle(.plain)
                }
            }
            if (store.snapshot.scheduleFailures ?? []).contains(schedule.metadata.id) {
                Text(store.language == "ru" ? "Не удалось поставить задачу в очередь. Проверьте агента и настройки расписания." : "Could not queue this run. Check its agent and schedule settings.")
                    .foregroundStyle(.red)
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
