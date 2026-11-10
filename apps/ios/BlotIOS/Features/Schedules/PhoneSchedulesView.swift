import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneSchedulesView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    private var selectedDate: Date { store.navigation.scheduleDate }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        @Bindable var navigation = store.navigation
        let content = PhoneScheduleDayContent(schedules: store.snapshot.schedules, day: selectedDate, calendar: calendar)
        return PhonePage {
            PhoneScheduleCalendar(selectedDate: $navigation.scheduleDate, calendar: calendar)
            PhoneSettingsGroup(title: selectedDate.formatted(.dateTime.day().month(.wide).locale(locale))) {
                if content.runs.isEmpty {
                    PhoneSettingsRow(title: "No runs on this day", detail: "Choose another day or create a schedule.", showsChevron: false)
                }
                ForEach(Array(content.runs.enumerated()), id: \.element.id) { index, run in
                    if index > 0 { PhoneSettingsDivider() }
                    schedule(run)
                }
            }
            Button { store.navigate(.createSchedule) } label: {
                BlotLabel(store.t("New schedule"), symbol: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(WorkspaceButtonStyle(.secondary))
            WorkspaceFeedback()
            if store.mode == .live {
                Text(store.t("Schedules run on the selected device. Exact background execution is not guaranteed on iPhone."))
                    .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
            }
        }
        .refreshable { await store.synchronizeAccount() }
    }

    private func schedule(_ run: PhoneScheduleDayContent.Run) -> some View {
        let schedule = run.schedule
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.t(schedule.name)).font(.subheadline.weight(.medium))
                    Text(run.date, format: .dateTime.hour().minute()).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle(store.t("Enabled"), isOn: Binding(get: { schedule.enabled }, set: { _ in
                    store.selectedRecordID = schedule.metadata.id
                    _Concurrency.Task { await store.perform(.updateSchedule) }
                })).labelsHidden().disabled(store.busy).accessibilityLabel(store.t(schedule.name))
            }
            Text(store.t(schedule.goal)).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
            BlotLabel(executorName(schedule), symbol: schedule.executorDeviceId == store.snapshot.localDeviceID ? "iphone" : "desktopcomputer")
                .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
            if store.mode == .live {
                WorkspaceScheduleRunSummary(schedule: schedule)
                Button(store.t("Run now")) { store.runScheduleManually(schedule.metadata.id) }
                    .buttonStyle(.bordered).disabled(store.busy)
            }
        }.padding(PhonePageLayout.rowInset)
    }

    private func executorName(_ schedule: BlotV3.Automation) -> String {
        if schedule.executorDeviceId == store.snapshot.localDeviceID { return store.t("This device") }
        return store.snapshot.devices.first { $0.metadata.id == schedule.executorDeviceId }?.name ?? store.t("Selected computer")
    }
}
