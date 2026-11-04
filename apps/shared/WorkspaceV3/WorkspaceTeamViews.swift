import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceTeamView: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        switch route {
        case .createAgent, .editAgent: editor
        case .agentProfile: profileDetails
        case .files: files
        case .schedules: schedules
        case .createSchedule: scheduleEditor
        default: agents
        }
    }
    private var visibleAgents: Array<BlotV3.AgentProfile> {
        #if os(macOS)
        store.snapshot.agents
        #else
        Array(store.snapshot.agents.prefix(4))
        #endif
    }
    private var agentColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 200), alignment: .top)]
        #else
        Array(repeating: GridItem(.flexible(), alignment: .top), count: 2)
        #endif
    }
    private var agents: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Your team", subtitle: "Each has its own role and context.")
            LazyVGrid(columns: agentColumns, spacing: 16) {
                ForEach(visibleAgents, id: \.metadata.id) { agent in
                    Button { store.selectAgent(agent.metadata.id) } label: {
                        WorkspaceCard(isButtonLabel: true) {
                            VStack(alignment: .leading, spacing: 18) {
                                WorkspaceAvatarView(agent: agent, size: 52)
                                Text(agent.name).font(.headline)
                                Text(store.t(agent.instructions)).font(.callout).foregroundStyle(WorkspaceStyle.secondary).lineLimit(3)
                                Text(store.t("Ready")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                            }.frame(minHeight: 160, alignment: .top)
                        }
                    }.buttonStyle(WorkspaceRowButtonStyle())
                }
            }
            WorkspaceLink(title: "Create an agent for your task", route: .createAgent, symbol: "plus")
            if store.snapshot.agents.isEmpty { WorkspaceDataState(state: .empty) }
        }
    }
    private var profileDetails: some View {
        @Bindable var store = store
        let agent = store.snapshot.agents.first(where: { $0.metadata.id == store.selectedAgentID }) ?? store.snapshot.agents.first
        return VStack(alignment: .leading, spacing: 26) {
            if let agent {
                HStack(spacing: 20) {
                    WorkspaceAvatarView(agent: agent, size: 74)
                    VStack(alignment: .leading, spacing: 6) { Text(agent.name).font(.largeTitle); Text(store.t("Ready")).foregroundStyle(WorkspaceStyle.secondary) }
                }
                Text(store.t(agent.instructions)).foregroundStyle(WorkspaceStyle.secondary)
                WorkspaceCard {
                    WorkspaceLink(title: "Instructions", route: .editAgent)
                    WorkspaceLink(title: "Model", route: .models)
                    WorkspaceLink(title: "Access mode", route: .permissions)
                    WorkspaceLink(title: "Skills", route: .mcp)
                }
                #if os(iOS)
                WorkspaceCard { WorkspaceLink(title: "Personalization", route: .personalization, symbol: "sliders") }
                #else
                WorkspaceCard { Toggle(store.t("Agent memory"), isOn: $store.form.agent.remember)
                    Text(store.t("Preferences and task context")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                    WorkspaceLink(title: "Edit memory", route: .memory) }
                #endif
                Button { _Concurrency.Task { await store.openAgentChat(agent.metadata.id) } } label: {
                    Text(store.t("Open chat"))
                        #if os(iOS)
                        .frame(maxWidth: .infinity)
                        #endif
                }.buttonStyle(WorkspaceButtonStyle())
            } else { WorkspaceDataState(state: .empty) }
        }
    }
    private var editor: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Who joins the team?", subtitle: "Describe the role — Blot keeps this agent’s instructions and context.")
            HStack(spacing: 20) {
                WorkspaceAvatar(shape: .init(rawValue: store.form.agent.shape) ?? .round, color: WorkspaceAvatarView.color(store.form.agent.color), size: 80)
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.t("Agent look")).font(.headline)
                    HStack { ForEach(["ink", "orange", "purple", "teal"], id: \.self) { c in
                        Button { store.form.agent.color = c } label: {
                            Circle().fill(WorkspaceAvatarView.color(c)).frame(width: 28, height: 28)
                                .padding(4).overlay(Circle().strokeBorder(store.form.agent.color == c ? WorkspaceStyle.ink : .clear))
                        }.buttonStyle(WorkspaceRowButtonStyle(padding: 0)).accessibilityLabel(store.t(c))
                    } }
                    Picker(store.t("Shape"), selection: $store.form.agent.shape) {
                        Text(store.t("Round")).tag("round"); Text(store.t("Triangle")).tag("triangle"); Text(store.t("Tall")).tag("tall")
                    }.pickerStyle(.segmented)
                }
            }
            WorkspaceField(title: "Name", text: $store.form.agent.name)
            WorkspaceField(title: "What it does", text: $store.form.agent.instructions, multiline: true)
            WorkspaceCard {
                WorkspaceLink(title: "Model", route: .models)
                WorkspaceLink(title: "Access", route: .permissions)
                WorkspaceLink(title: "Computer", route: .devices)
            }
            Toggle(store.t("Remember useful context"), isOn: $store.form.agent.remember)
            WorkspaceFeedback()
            WorkspaceV3ActionButton(title: route == .editAgent ? "Save agent" : "Create agent", action: route == .editAgent ? .saveAgent : .createAgent, next: .agents)
        }
    }
    private var files: some View {
        #if os(iOS)
        PhoneFilesContent()
        #else
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 22) {
            WorkspaceHeading(title: "Files", subtitle: "Workspace results and documents")
            WorkspaceField(title: "Search by name and content", text: $store.form.search.query)
            ForEach(store.snapshot.artifacts.filter { store.form.search.query.isEmpty || $0.name.localizedCaseInsensitiveContains(store.form.search.query) }, id: \.metadata.id) { file in
                Button { store.selectedRecordID = file.metadata.id; store.navigate(.file) } label: {
                    HStack { BlotIcon(symbol: "doc"); Text(file.name); Spacer(); BlotIcon(symbol: "chevron.right") }
                }.buttonStyle(WorkspaceRowButtonStyle())
                Divider()
            }
            if store.snapshot.artifacts.isEmpty { WorkspaceDataState(state: .empty) }
            Text(store.t("Files stay on this computer. Results are available on linked devices.")).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
        }
        #endif
    }
    private var schedules: some View {
        VStack(alignment: .leading, spacing: 24) {
            #if os(macOS)
            WorkspaceHeading(title: "Schedules", subtitle: "Your team works on your rhythm.")
            #else
            Text(store.t("Your team works on your rhythm.")).foregroundStyle(WorkspaceStyle.secondary)
            #endif
            if store.mode != .live { week }
            ForEach(store.snapshot.schedules, id: \.metadata.id) { schedule in
                WorkspaceCard {
                    HStack(alignment: .top, spacing: 14) {
                        WorkspaceAvatar(color: WorkspaceAvatarView.color(schedule.name == "Morning digest" ? "ink" : "teal"), size: 38)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.t(schedule.name)).font(.headline)
                            Text(schedule.localTime + " · " + schedule.timezone).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                            if store.mode == .live, let next = try? WorkspaceScheduleCalculator().nextRun(for: schedule, after: Date()) {
                                Text(next, format: .dateTime.day().month().hour().minute())
                                    .environment(\.timeZone, TimeZone(identifier: schedule.timezone) ?? .current).font(.caption)
                            }
                            Text(store.t(schedule.goal)).foregroundStyle(WorkspaceStyle.secondary)
                            BlotLabel("MacBook Pro", symbol: "laptopcomputer").font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                        }
                        Spacer(minLength: 0)
                        Toggle(store.t("Enabled"), isOn: Binding(get: { schedule.enabled }, set: { _ in
                            store.selectedRecordID = schedule.metadata.id
                            _Concurrency.Task { await store.perform(.updateSchedule) }
                        })).labelsHidden().disabled(store.busy).accessibilityLabel(store.t(schedule.name))
                    }
                    if store.mode == .live { Button(store.t("Run now")) { store.runScheduleManually(schedule.metadata.id) }.disabled(store.busy) }
                }
            }
            WorkspaceLink(title: "New schedule", route: .createSchedule, symbol: "plus")
            if store.snapshot.schedules.isEmpty { WorkspaceDataState(state: .empty) }
            WorkspaceFeedback()
        }
    }
    private var week: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].enumerated()), id: \.offset) { i, day in
                VStack(alignment: .leading, spacing: 18) {
                    Text(store.t(day)).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                    Text("\(i + 2)").font(.title2)
                    if i < 5 {
                        VStack(alignment: .leading, spacing: 8) { Text("08:30").font(.caption.monospaced()); Text(store.t("Morning digest")) }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(i == 0 ? BlotColor.onInverse : WorkspaceStyle.ink)
                            .background(i == 0 ? BlotColor.inverse : WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                }.padding(12).frame(maxWidth: .infinity).frame(height: 290).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        #else
        HStack(spacing: 8) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { i, day in
                VStack(spacing: 10) { Text(day).font(.caption); Text("\(i + 2)").font(.title3) }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(i == 0 ? BlotColor.onInverse : WorkspaceStyle.ink)
                    .background(i == 0 ? BlotColor.inverse : WorkspaceStyle.surface, in: Capsule())
            }
        }.accessibilityLabel(store.t("Week of November 2"))
        #endif
    }
    private var scheduleEditor: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Start the morning with a clear plan", subtitle: "Set what to do, when to run and where to show the result.")
            WorkspaceField(title: "Name", text: $store.form.schedule.name)
            WorkspaceCard {
                DatePicker(store.t("Run time"), selection: $store.form.schedule.time, displayedComponents: .hourAndMinute)
                if store.mode == .live {
                    Toggle(store.t("One-time"), isOn: $store.form.schedule.oneTime)
                    if store.form.schedule.oneTime { DatePicker(store.t("Date"), selection: $store.form.schedule.time, displayedComponents: .date) }
                    WorkspaceField(title: "Time zone", text: $store.form.schedule.timezone)
                } else { Text("Asia/Yekaterinburg · UTC+5").font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
            }
            HStack {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { i, day in
                    Button { if store.form.schedule.weekdays.contains(i+1) { store.form.schedule.weekdays.remove(i+1) } else { store.form.schedule.weekdays.insert(i+1) } } label: {
                        Text(day).frame(maxWidth: .infinity, minHeight: 44)
                            #if os(iOS)
                            .foregroundStyle(WorkspaceStyle.ink)
                            .fontWeight(store.form.schedule.weekdays.contains(i+1) ? .bold : .regular)
                            #else
                            .foregroundStyle(store.form.schedule.weekdays.contains(i+1) ? BlotColor.onInverse : WorkspaceStyle.ink)
                            .background(store.form.schedule.weekdays.contains(i+1) ? BlotColor.inverse : WorkspaceStyle.surface, in: Circle())
                            #endif
                    }.buttonStyle(WorkspaceRowButtonStyle(padding: 0)).accessibilityLabel(store.t("Weekday") + " \(i+1)").accessibilityValue(store.form.schedule.weekdays.contains(i+1) ? store.t("Selected") : store.t("Not selected"))
                }
            }
            WorkspaceField(title: "What to do", text: $store.form.schedule.goal, multiline: true)
            if store.mode == .live {
                Picker(store.t("Agent"), selection: $store.form.schedule.agentID) {
                    Text(store.t("Not selected")).tag(nil as UUID?)
                    ForEach(store.snapshot.agents, id: \.metadata.id) { agent in Text(agent.name).tag(Optional(agent.metadata.id)) }
                }
                Picker(store.t("Run tasks on"), selection: $store.form.schedule.deviceID) {
                    Text(store.t("Not selected")).tag(nil as UUID?)
                    if let id = store.snapshot.localDeviceID { Text(store.t("This device")).tag(Optional(id)) }
                    ForEach(store.snapshot.devices, id: \.metadata.id) { device in Text(device.name).tag(Optional(device.metadata.id)) }
                }
                Picker(store.t("Missed runs"), selection: $store.form.schedule.missedRunPolicy) {
                    ForEach(BlotV3.MissedRunPolicy.allCases, id: \.self) { policy in Text(policy.rawValue).tag(policy) }
                }
            }
            WorkspaceCard { WorkspaceLink(title: "Agent", route: .agents); WorkspaceLink(title: "Computer", route: .devices)
                Text(store.t("Missed run: one combined run when the computer returns.")).font(.footnote).foregroundStyle(WorkspaceStyle.secondary) }
            WorkspaceFeedback()
            WorkspaceV3ActionButton(title: "Create schedule", action: .createSchedule, next: .schedules)
        }
    }
}
