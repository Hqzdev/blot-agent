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
                    DatePicker(store.t("Run time"), selection: $store.form.schedule.time,
                        displayedComponents: store.form.schedule.oneTime ? [.date, .hourAndMinute] : .hourAndMinute)
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
                        Picker(store.t("Missed runs"), selection: $store.form.schedule.missedRunPolicy) {
                            ForEach(BlotV3.MissedRunPolicy.allCases, id: \.self) { policy in WorkspaceSchedulePolicyLabel(policy: policy).tag(policy) }
                        }
                        if store.form.schedule.missedRunPolicy == .catch_up {
                            Stepper(store.t("Maximum catch-up runs") + ": \(store.form.schedule.maximumCatchUpRuns)", value: $store.form.schedule.maximumCatchUpRuns, in: 1...100)
                        }
                    } else { Text(TimeZone.current.identifier).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
                }.padding(PhonePageLayout.rowInset)
            }
            PhoneSettingsGroup(title: "Agent") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(store.t("Agent"), selection: $store.form.schedule.agentID) {
                        Text(store.t("Just chat with AI")).tag(nil as UUID?)
                        ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                            Text(agent.name).tag(Optional(agent.metadata.id))
                        }
                    }
                    Picker(store.t("Computer"), selection: $store.form.schedule.deviceID) {
                        Text(store.t("Not selected")).tag(nil as UUID?)
                        if store.mode == .live, let id = store.snapshot.localDeviceID { Text(store.t("This iPhone")).tag(Optional(id)) }
                        ForEach(store.snapshot.devices.filter { $0.kind == .desktop }, id: \.metadata.id) { device in
                            Text(device.name).tag(Optional(device.metadata.id))
                        }
                    }
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
        }.textFieldStyle(.roundedBorder)
    }

    private func dayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: store.language == "ru" ? "ru_RU" : "en_GB")
        return formatter.veryShortStandaloneWeekdaySymbols[weekday % 7]
    }
}
