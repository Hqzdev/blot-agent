import BlotDesign
import BlotDomain
import SwiftUI

struct MacWorkspaceInspector: View {
    @Environment(WorkspaceStore.self) private var store
    private var agent: BlotV3.AgentProfile? { store.snapshot.agents.first { $0.metadata.id == store.currentConversation?.agentId } }
    private var routines: [BlotV3.Automation] { store.snapshot.schedules.filter { $0.agentId == agent?.metadata.id } }
    private var summary: String { ([agent?.name ?? "Blot Agent"] + routines.map { "\($0.name) · \($0.localTime)" }).joined(separator: "\n") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { store.inspectorVisible = false } label: { BlotIcon(.chevronLeft, size: 13) }
                    .help(store.t("Back"))
                Spacer()
                ShareLink(item: summary) { BlotIcon(.share, size: 14) }.help(store.t("Share"))
                Button { if let agent { store.selectAgent(agent.metadata.id) } } label: { BlotIcon(.settings, size: 14) }
                    .disabled(agent == nil).help(store.t("Agent"))
                Button { store.inspectorVisible = false } label: { BlotIcon(.close, size: 14) }.help(store.t("Close"))
            }.buttonStyle(.plain).foregroundStyle(WorkspaceStyle.secondary)
                .padding(.horizontal, 14).frame(height: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 8) {
                        if store.isPreview {
                            MacAgentCalendarPreview(routines: routines)
                                .aspectRatio(1.5, contentMode: .fit)
                            Text(store.t("Agent screen"))
                                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                        } else {
                            Button { store.navigate(.devices) } label: {
                                VStack(spacing: 10) { BlotIcon(.computer, size: 28); Text(store.t("Connect computer")) }
                                    .frame(maxWidth: .infinity).frame(height: 150)
                                    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: BlotRadius.panel))
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(store.t("Routines")).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                            Spacer()
                            Button(action: createSchedule) { BlotIcon(.plus, size: 12) }
                                .buttonStyle(.plain).help(store.t("Create schedule"))
                        }
                        ForEach(routines, id: \.metadata.id) { routine in
                            HStack(spacing: 10) {
                                Button {
                                    store.selectedRecordID = routine.metadata.id
                                    _Concurrency.Task { await store.perform(.updateSchedule) }
                                } label: {
                                    BlotIcon(routine.enabled ? .progress : .pause, size: 15)
                                        .foregroundStyle(routine.enabled ? Color.teal : WorkspaceStyle.secondary)
                                }.buttonStyle(.plain).disabled(store.busy)
                                    .help(store.t(routine.enabled ? "Pause" : "Resume"))
                                Button { store.navigate(.schedules) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(store.t(routine.name)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        Text(scheduleDescription(routine)).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        if routines.isEmpty {
                            Text(store.t("No routines yet")).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                        }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }.background(WorkspaceStyle.canvas)
    }

    private func scheduleDescription(_ routine: BlotV3.Automation) -> String {
        guard routine.enabled else { return store.t("Paused") }
        if Set(routine.weekdays) == Set(1...7) { return store.t("Every day") + " · " + routine.localTime }
        if Set(routine.weekdays) == Set(1...5) { return store.t("Weekdays") + " · " + routine.localTime }
        return routine.weekdays.map { day in
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: store.language)
            return calendar.shortWeekdaySymbols[(day % 7)]
        }.joined(separator: ", ") + " · " + routine.localTime
    }

    private func createSchedule() {
        store.form.schedule = WorkspaceScheduleForm()
        store.form.schedule.agentID = agent?.metadata.id
        store.form.schedule.deviceID = store.snapshot.devices.first { $0.kind == .desktop }?.metadata.id
        store.navigate(.createSchedule)
    }
}
