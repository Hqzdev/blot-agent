import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceTeamView: View {
    let route: WorkspaceRoute
    var openFile: ((UUID) -> Void)? = nil
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    @State private var fileQuery = ""
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
                    Button {
                        store.selectAgent(agent.metadata.id, navigating: panelNavigation == nil)
                        panelNavigation?.open(.agentProfile)
                    } label: {
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
                    WorkspaceLink(title: "Skills", route: .skills)
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
            WorkspaceHeading(title: "Who joins the team?", subtitle: "Describe the role — Ori keeps this agent’s instructions and context.")
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
                    WorkspaceChoice(title: store.t("Shape"), selection: $store.form.agent.shape, options: [.init("round", store.t("Round")), .init("triangle", store.t("Triangle")), .init("tall", store.t("Tall"))])
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
        let search = if let panelNavigation { Bindable(panelNavigation).fileQuery } else { $fileQuery }
        let query = search.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = store.visibleFiles
        let matches = query.isEmpty ? files : files.filter { $0.name.localizedStandardContains(query) }
        return VStack(alignment: .leading, spacing: 22) {
            WorkspaceHeading(title: "Files", subtitle: "Workspace results and documents")
            WorkspacePagesButton()
            WorkspaceFilesImportButton()
            WorkspaceField(title: "Search by name", text: search)
            ForEach(matches, id: \.metadata.id) { file in
                Button {
                    if let openFile { openFile(file.metadata.id) }
                    else { store.selectedRecordID = file.metadata.id; store.navigate(.file) }
                } label: {
                    HStack { BlotIcon(symbol: "doc"); Text(file.name); Spacer(); BlotIcon(symbol: "chevron.right") }
                }.buttonStyle(WorkspaceRowButtonStyle())
                Divider()
            }
            if files.isEmpty {
                Text(store.language == "ru" ? "Файлов пока нет" : "No files yet")
                    .foregroundStyle(WorkspaceStyle.secondary)
            } else if matches.isEmpty {
                Text(store.language == "ru" ? "По этому имени ничего не найдено" : "No files match this name")
                    .foregroundStyle(WorkspaceStyle.secondary)
                Button(store.language == "ru" ? "Очистить поиск" : "Clear search") { search.wrappedValue = "" }
                    .buttonStyle(WorkspaceButtonStyle(.secondary))
            }
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
            #if os(macOS)
            upcomingSchedules
            #else
            if store.mode != .live { week }
            #endif
            ForEach(store.snapshot.schedules, id: \.metadata.id) { schedule in
                WorkspaceCard {
                    HStack(alignment: .top, spacing: 14) {
                        WorkspaceAvatar(color: WorkspaceAvatarView.color(schedule.name == "Morning digest" ? "ink" : "teal"), size: 38)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.t(schedule.name)).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Text(schedule.localTime + " · " + schedule.timezone).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                            if store.mode == .live { WorkspaceScheduleRunSummary(schedule: schedule) }
                            Text(store.t(schedule.goal)).foregroundStyle(WorkspaceStyle.secondary)
                            BlotLabel(executorName(schedule), symbol: "laptopcomputer").font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                        }
                        Spacer(minLength: 0)
                        Toggle(store.t("Enabled"), isOn: Binding(get: { schedule.enabled }, set: { _ in
                            store.selectedRecordID = schedule.metadata.id
                            _Concurrency.Task { await store.perform(.updateSchedule) }
                        })).labelsHidden().disabled(store.busy).accessibilityLabel(store.t(schedule.name))
                    }
                    if store.mode == .live {
                        HStack {
                            Button(store.t("Run now")) { store.runScheduleManually(schedule.metadata.id) }.disabled(store.busy)
                            WorkspaceRoutineActions(schedule: schedule)
                        }
                    }
                }
            }
            WorkspaceLink(title: "New schedule", route: .createSchedule, symbol: "plus")
            if store.snapshot.schedules.isEmpty { WorkspaceDataState(state: .empty) }
            WorkspaceFeedback()
            if store.mode == .live {
                Text(store.language == "ru" ? "На Mac расписания работают, пока Ori запущен, в том числе при свёрнутом окне. После сна или перезапуска применяется выбранная политика пропущенных запусков. На iPhone точное выполнение в фоне не гарантируется." : "On Mac, schedules run while Ori is running, including with its window minimized. Missed-run policy applies after sleep or restart. Exact background execution is not guaranteed on iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func executorName(_ schedule: BlotV3.Automation) -> String {
        if schedule.executorDeviceId == store.snapshot.localDeviceID { return store.t("This device") }
        return store.snapshot.devices.first { $0.metadata.id == schedule.executorDeviceId }?.name ?? store.t("Selected computer")
    }
    #if os(macOS)
    private var upcomingSchedules: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let calculator = WorkspaceScheduleCalculator()
            let upcoming = store.snapshot.schedules.compactMap { schedule -> (schedule: BlotV3.Automation, date: Date)? in
                guard let date = try? calculator.nextRun(for: schedule, after: context.date) else { return nil }
                return (schedule, date)
            }.sorted { $0.date < $1.date }
            if !upcoming.isEmpty {
                WorkspaceCard {
                    Text(store.language == "ru" ? "Ближайшие запуски" : "Upcoming runs")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(Array(upcoming.prefix(7)), id: \.schedule.metadata.id) { item in
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text(store.t(item.schedule.name)).lineLimit(1).fixedSize()
                                Spacer(minLength: 12)
                                Text(item.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                                    .foregroundStyle(WorkspaceStyle.secondary).fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.t(item.schedule.name))
                                Text(item.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                                    .foregroundStyle(WorkspaceStyle.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
    #else
    private var week: some View {
        HStack(spacing: 8) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { i, day in
                VStack(spacing: 10) { Text(day).font(.caption); Text("\(i + 2)").font(.title3) }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(i == 0 ? BlotColor.onInverse : WorkspaceStyle.ink)
                    .background(i == 0 ? BlotColor.inverse : WorkspaceStyle.surface, in: Capsule())
            }
        }.accessibilityLabel(store.t("Week of November 2"))
    }
    #endif
    private var scheduleEditor: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Start the morning with a clear plan", subtitle: "Set what to do, when to run and where to show the result.")
            WorkspaceField(title: "Name", text: $store.form.schedule.name)
            WorkspaceCard {
                WorkspacePanelDateField(title: store.t("Run time"), date: $store.form.schedule.time)
                if store.mode == .live {
                    Toggle(store.t("One-time"), isOn: $store.form.schedule.oneTime)
                    if store.form.schedule.oneTime { WorkspacePanelDateField(title: store.t("Date"), date: $store.form.schedule.time, calendarOnly: true) }
                    WorkspaceField(title: "Time zone", text: $store.form.schedule.timezone)
                } else { Text("Asia/Yekaterinburg · UTC+5").font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
            }
            let formatter = DateFormatter()
            let _ = formatter.locale = Locale(identifier: store.language)
            HStack {
                ForEach(1...7, id: \.self) { day in
                    let index = day % 7
                    let selected = store.form.schedule.weekdays.contains(day)
                    Button {
                        if selected { store.form.schedule.weekdays.remove(day) }
                        else { store.form.schedule.weekdays.insert(day) }
                    } label: {
                        Text(formatter.veryShortStandaloneWeekdaySymbols[index]).frame(maxWidth: .infinity, minHeight: 44)
                            #if os(iOS)
                            .foregroundStyle(WorkspaceStyle.ink)
                            .fontWeight(selected ? .bold : .regular)
                            #else
                            .foregroundStyle(selected ? BlotColor.onInverse : WorkspaceStyle.ink)
                            .background(selected ? BlotColor.inverse : WorkspaceStyle.surface, in: Capsule())
                            #endif
                    }.buttonStyle(WorkspaceRowButtonStyle(padding: 0))
                        .accessibilityLabel(formatter.standaloneWeekdaySymbols[index])
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            WorkspaceField(title: "What to do", text: $store.form.schedule.goal, multiline: true)
            if store.mode == .live {
                WorkspaceChoice(title: store.t("Agent"), selection: $store.form.schedule.agentID,
                    options: [.init(nil, store.t("Not selected"))] + store.snapshot.agents.map { .init(Optional($0.metadata.id), $0.name) })
                WorkspaceChoice(title: store.t("Run tasks on"), selection: $store.form.schedule.deviceID,
                    options: [.init(nil, store.t("Not selected"))] + (store.snapshot.localDeviceID.map { [.init(Optional($0), store.t("This device"))] } ?? []) + store.snapshot.devices.filter { $0.metadata.id != store.snapshot.localDeviceID }.map { .init(Optional($0.metadata.id), $0.name) })
                WorkspaceChoice(title: store.t("Missed runs"), selection: $store.form.schedule.missedRunPolicy,
                    options: BlotV3.MissedRunPolicy.allCases.map { .init($0, WorkspaceSchedulePolicyLabel.title($0, russian: store.language == "ru")) })
                if store.form.schedule.missedRunPolicy == .catch_up {
                    WorkspaceCounter(title: store.t("Maximum catch-up runs"), value: $store.form.schedule.maximumCatchUpRuns, range: 1...100)
                }
            }
            WorkspaceCard { WorkspaceLink(title: "Agent", route: .agents); WorkspaceLink(title: "Computer", route: .devices)
                Text(store.t("Missed run: one combined run when the computer returns.")).font(.footnote).foregroundStyle(WorkspaceStyle.secondary) }
            WorkspaceFeedback()
            WorkspaceV3ActionButton(title: "Create schedule", action: .createSchedule, next: .schedules)
        }
    }
}
