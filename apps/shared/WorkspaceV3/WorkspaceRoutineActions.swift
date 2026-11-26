import BlotDesign
import BlotDomain
import SwiftUI

/// Both clients use the same editing and deletion flow; the calendar remains platform-specific.
struct WorkspaceRoutineActions: View {
    let schedule: BlotV3.Automation
    @Environment(WorkspaceStore.self) private var store
    @State private var editing = false
    @State private var deleting = false
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        HStack(spacing: 16) {
            Button(ru ? "Изменить" : "Edit") { editing = true }
            Button(ru ? "Удалить" : "Delete", role: .destructive) { deleting = true }
        }
        .disabled(store.busy)
        .workspacePanelSheet(isPresented: $editing) { WorkspaceRoutineEditor(schedule: schedule).environment(store) }
        .workspaceConfirmationDialog(ru ? "Удалить «\(schedule.name)»?" : "Delete “\(schedule.name)”?", isPresented: $deleting, titleVisibility: .visible) {
            Button(store.t("Delete"), role: .destructive) {
                store.selectedRecordID = schedule.metadata.id
                _Concurrency.Task { await store.perform(.deleteSchedule) }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(ru ? "Новых запусков не будет. Уже созданные задачи и их результаты сохранятся." : "Future runs will stop. Existing tasks and their results will be kept.")
        }
    }
}

struct WorkspaceRoutineEditor: View {
    let schedule: BlotV3.Automation
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var draft: WorkspaceScheduleForm
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    init(schedule: BlotV3.Automation) {
        self.schedule = schedule
        var form = WorkspaceScheduleForm()
        form.recordID = schedule.metadata.id; form.version = schedule.metadata.version
        form.name = schedule.name; form.goal = schedule.goal; form.timezone = schedule.timezone
        form.agentID = schedule.agentId; form.deviceID = schedule.executorDeviceId
        form.skillRevisionID = schedule.skillRevisionId; form.enabled = schedule.enabled
        form.missedRunPolicy = schedule.missedRunPolicy; form.maximumCatchUpRuns = schedule.maxCatchUpRuns ?? 1
        form.weekdays = Set(schedule.weekdays); form.oneTime = schedule.scheduledAt != nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timezone) ?? .current
        let parts = schedule.localTime.split(separator: ":").compactMap { Int($0) }
        form.time = schedule.scheduledAt ?? calendar.date(bySettingHour: parts.first ?? 9,
            minute: parts.dropFirst().first ?? 0, second: 0, of: Date()) ?? Date()
        _draft = State(initialValue: form)
    }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                Section(ru ? "Задание" : "Task") {
                    TextField(store.t("Name"), text: $draft.name)
                    TextField(store.t("What to do"), text: $draft.goal, axis: .vertical).lineLimit(3...10)
                    Toggle(store.t("Enabled"), isOn: $draft.enabled)
                }
                Section(ru ? "Время запуска" : "When to run") {
                    Toggle(store.t("One-time"), isOn: $draft.oneTime)
                    if draft.oneTime {
                        WorkspacePanelDateField(title: store.t("Date"), date: $draft.time, calendarOnly: true)
                            .environment(\.timeZone, TimeZone(identifier: draft.timezone) ?? .current)
                    }
                    WorkspacePanelDateField(title: store.t("Run time"), date: $draft.time)
                        .environment(\.timeZone, TimeZone(identifier: draft.timezone) ?? .current)
                    TextField(store.t("Time zone"), text: $draft.timezone)
                    if !draft.oneTime {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(dayName(day), isOn: Binding(get: { draft.weekdays.contains(day) }, set: {
                                if $0 { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) }
                            }))
                        }
                    }
                    WorkspaceChoice(title: store.t("Missed runs"), selection: $draft.missedRunPolicy, options: BlotV3.MissedRunPolicy.allCases.map { .init($0, WorkspaceSchedulePolicyLabel.title($0, russian: ru)) })
                    if draft.missedRunPolicy == .catch_up {
                        WorkspaceCounter(title: store.t("Maximum catch-up runs"), value: $draft.maximumCatchUpRuns, range: 1...100)
                    }
                }
                Section(store.t("Agent")) {
                    WorkspaceChoice(title: store.t("Agent"), selection: $draft.agentID, options: [.init(nil, store.t("Not selected"))] + store.snapshot.agents.map { .init(Optional($0.metadata.id), $0.name) })
                    WorkspaceChoice(title: store.t("Computer"), selection: $draft.deviceID, options: deviceOptions)
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "Изменить регулярную задачу" : "Edit routine") {
                    Button(store.t("Cancel")) { dismiss() }.disabled(store.busy)
                    Button(store.t("Save")) {
                        _Concurrency.Task {
                            if await store.saveRoutine(draft) { dismiss() }
                            else { failure = store.error }
                        }
                    }.buttonStyle(WorkspaceButtonStyle(.primary)).disabled(store.busy || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.workspaceEditorChrome()
        }
        .interactiveDismissDisabled(store.busy)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 500, idealHeight: 650)
        #endif
    }
    private var deviceOptions: [WorkspaceChoiceOption<UUID?>] {
        var values: [WorkspaceChoiceOption<UUID?>] = [.init(nil, store.t("Not selected"))]
        if let id = store.snapshot.localDeviceID { values.append(.init(id, store.t("This device"))) }
        values += store.snapshot.devices.filter { $0.metadata.id != store.snapshot.localDeviceID }.map { .init($0.metadata.id, $0.name) }
        return values
    }
    private func dayName(_ day: Int) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: ru ? "ru_RU" : "en_GB")
        return formatter.weekdaySymbols[day % 7]
    }
}
