import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceTaskExecutionView: View {
    var taskID: UUID? = nil
    @Environment(WorkspaceStore.self) private var store
    @State private var goal = ""
    @State private var executorID: UUID?
    @State private var projectID: UUID?
    private var tasks: [BlotV3.Task] {
        let tasks = (store.snapshot.tasks ?? []).filter { task in
            if let taskID { return task.metadata.id == taskID }
            return task.conversationId == store.selectedConversationID
        }
            .sorted { $0.metadata.createdAt > $1.metadata.createdAt }
        #if os(iOS)
        if let selected = tasks.first(where: { $0.metadata.id == store.selectedRecordID }) { return [selected] }
        #endif
        return tasks
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceHeading(title: "Tasks")
            WorkspaceNativeProjectButton()
            TextField(store.language == "ru" ? "Что нужно сделать?" : "What needs to be done?", text: $goal, axis: .vertical)
                .textFieldStyle(WorkspacePanelTextFieldStyle()).lineLimit(2...6)
            if store.deviceCommands != nil, store.currentConversation?.kind != .group {
                WorkspaceChoice(title: store.language == "ru" ? "Где выполнить" : "Run on", selection: $executorID,
                    options: [.init(nil, store.language == "ru" ? "Это устройство" : "This device")] + (store.snapshot.pairedDevices ?? []).filter { !$0.revoked && $0.kind == .desktop }.map { .init(Optional($0.id), $0.name) })
            }
            WorkspaceChoice(title: store.language == "ru" ? "Проект" : "Project", selection: $projectID,
                options: [.init(nil, store.language == "ru" ? "Без проекта" : "No project")] + (store.snapshot.projects ?? []).filter { $0.repositoryPath == "device:" + (executorID ?? store.snapshot.localDeviceID ?? UUID()).uuidString }.map { .init(Optional($0.metadata.id), $0.name) })
            .onChange(of: executorID) { _, _ in projectID = nil }
            Button(store.t("Start")) {
                let submitted = goal
                _Concurrency.Task {
                    let success = if let executorID { await store.delegateTask(goal: submitted, deviceID: executorID, projectID: projectID) } else { await store.createTask(goal: submitted, projectID: projectID) }
                    if success, goal == submitted { goal = "" }
                }
            }.buttonStyle(WorkspaceButtonStyle()).disabled(store.busy || goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(tasks, id: \.metadata.id) { task in
                WorkspaceCard {
                    if let revisionID = task.skillRevisionId,
                       let revision = store.snapshot.skillRevisions?.first(where: { $0.metadata.id == revisionID }),
                       let skill = store.snapshot.skills?.first(where: { $0.metadata.id == revision.skillId }) {
                        Label(skill.name, systemImage: "shippingbox").foregroundStyle(.purple)
                        Text(revision.metadata.createdAt, format: .dateTime.day().month().hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(task.goal).font(.headline).textSelection(.enabled)
                    WorkspaceTaskStateLabel(state: task.state).font(.callout).foregroundStyle(.secondary)
                    let local = task.execution.executorDeviceId == store.snapshot.localDeviceID && (task.executionMode == .local_owned || task.executionMode == .delegated)
                    if !local, task.executionMode == .delegated {
                        Text(store.language == "ru" ? "Ожидает выбранный Mac. Blot на Mac должен быть открыт; результат появится после синхронизации." : "Waiting for the selected Mac. Blot must be open there; results appear after sync.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !local, task.execution.originDeviceId == store.snapshot.localDeviceID, ![.completed, .failed, .canceled].contains(task.state) {
                        Button(store.t("Stop task"), role: .destructive) { control(.stop, task: task) }.disabled(store.busy)
                    }
                    if local, ![.completed, .failed, .canceled].contains(task.state) {
                        HStack {
                            if [.queued, .running, .planning].contains(task.state) {
                                Button(store.t("Pause")) { control(.pause, task: task) }
                            } else if [.paused, .interrupted, .waiting_user].contains(task.state) {
                                Button(store.t("Resume")) { control(.start, task: task) }
                            }
                            Button(store.t("Stop task"), role: .destructive) { control(.stop, task: task) }
                        }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(store.busy)
                    }
                    if task.state == .interrupted {
                        Text(store.language == "ru" ? "Прогресс сохранён. Если результат внешнего действия неизвестен, сначала проверьте его в подключении приложения." : "Progress is saved. Resolve any unknown external action outcome in its app connection before continuing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            WorkspaceFeedback()
        }.frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
    }
    private func control(_ action: WorkspaceAction, task: BlotV3.Task) {
        store.selectedRecordID = task.metadata.id
        _Concurrency.Task { await store.perform(action) }
    }
}
