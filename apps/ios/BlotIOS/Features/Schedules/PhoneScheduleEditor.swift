import BlotDesign
import BlotDomain
import Foundation
import SwiftUI

struct PhoneScheduleEditor: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "What to do") {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(store.t("Name"), text: $store.form.schedule.name)
                    TextField(store.t("What to do"), text: $store.form.schedule.goal, axis: .vertical).lineLimit(3...8)
                }.padding(PhonePageLayout.rowInset)
            }
            PhoneSettingsGroup(title: "Schedules") {
                VStack(alignment: .leading, spacing: 16) {
                    if store.mode == .live { Toggle(store.t("One-time"), isOn: $store.form.schedule.oneTime) }
                    if store.form.schedule.oneTime {
                        WorkspacePanelDateField(title: store.t("Date"), date: $store.form.schedule.time, calendarOnly: true)
                            .environment(\.timeZone, TimeZone(identifier: store.form.schedule.timezone) ?? .current)
                    }
                    WorkspacePanelDateField(title: store.t("Run time"), date: $store.form.schedule.time)
                        .environment(\.timeZone, TimeZone(identifier: store.form.schedule.timezone) ?? .current)
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { weekday in
                            Button {
                                if store.form.schedule.weekdays.contains(weekday) { store.form.schedule.weekdays.remove(weekday) }
                                else { store.form.schedule.weekdays.insert(weekday) }
                            } label: {
                                Text(dayName(weekday)).font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(store.form.schedule.weekdays.contains(weekday) ? BlotColor.onInverse : WorkspaceStyle.ink)
                                    .background(store.form.schedule.weekdays.contains(weekday) ? BlotColor.inverse : WorkspaceStyle.surface, in: Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(store.form.schedule.weekdays.contains(weekday) ? .isSelected : [])
                        }
                    }
                    if store.mode == .live {
                        TextField(store.t("Time zone"), text: $store.form.schedule.timezone).autocorrectionDisabled().textInputAutocapitalization(.never)
                        WorkspaceChoice(title: store.t("Missed runs"), selection: $store.form.schedule.missedRunPolicy, options: BlotV3.MissedRunPolicy.allCases.map { .init($0, WorkspaceSchedulePolicyLabel.title($0, russian: store.language == "ru")) })
                        if store.form.schedule.missedRunPolicy == .catch_up {
                            WorkspaceCounter(title: store.t("Maximum catch-up runs"), value: $store.form.schedule.maximumCatchUpRuns, range: 1...100)
                        }
                    } else { Text(TimeZone.current.identifier).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
                }.padding(PhonePageLayout.rowInset)
            }
            PhoneSettingsGroup(title: "Agent") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceChoice(title: store.t("Agent"), selection: $store.form.schedule.agentID, options: [.init(nil, store.t("Just chat with AI"))] + store.snapshot.agents.map { .init(Optional($0.metadata.id), $0.name) })
                    WorkspaceChoice(title: store.t("Computer"), selection: $store.form.schedule.deviceID, options: deviceOptions)
                    if store.mode != .live && store.snapshot.devices.allSatisfy({ $0.kind != .desktop }) {
                        Button(store.t("Connect computer")) { store.navigate(.pair) }
                    }
                }.padding(PhonePageLayout.rowInset)
            }
            VStack(alignment: .leading, spacing: 16) {
                Button { _Concurrency.Task { await store.saveSchedule() } } label: {
                    Text(store.t("Create schedule")).frame(maxWidth: .infinity)
                }.buttonStyle(WorkspaceButtonStyle())
                    .disabled(store.busy || store.form.schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || store.form.schedule.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (!store.form.schedule.oneTime && store.form.schedule.weekdays.isEmpty))
                WorkspaceFeedback()
            }
        }.textFieldStyle(BlotTextFieldStyle())
    }

    private var deviceOptions: [WorkspaceChoiceOption<UUID?>] {
        var values: [WorkspaceChoiceOption<UUID?>] = [.init(nil, store.t("Not selected"))]
        if store.mode == .live, let id = store.snapshot.localDeviceID { values.append(.init(id, store.t("This iPhone"))) }
        values += store.snapshot.devices.filter { $0.kind == .desktop && $0.metadata.id != store.snapshot.localDeviceID }.map { .init($0.metadata.id, $0.name) }
        return values
    }

    private func dayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: store.language == "ru" ? "ru_RU" : "en_GB")
        return formatter.veryShortStandaloneWeekdaySymbols[weekday % 7]
    }
}
