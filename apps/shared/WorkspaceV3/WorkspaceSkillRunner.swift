import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceSkillRunner: View {
    let skill: BlotV3.Skill
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var revisionID: UUID?
    @State private var agentID: UUID?
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var revisions: [BlotV3.SkillRevision] { (store.snapshot.skillRevisions ?? []).filter { $0.skillId == skill.metadata.id }.sorted { $0.metadata.createdAt > $1.metadata.createdAt } }
    private var revision: BlotV3.SkillRevision? { revisions.first { $0.metadata.id == (revisionID ?? skill.activeRevisionId) } }
    private var parameters: [SkillParameter] { revision.flatMap { try? WorkspaceSkillService.parameters($0) } ?? [] }
    private var agents: [BlotV3.AgentProfile] {
        let assigned = Set((store.snapshot.skillAssignments ?? []).filter { $0.skillID == skill.metadata.id && $0.assigned }.map(\.agentID))
        return store.snapshot.agents.filter { assigned.contains($0.metadata.id) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(ru ? "Версия" : "Revision", selection: $revisionID) {
                        ForEach(revisions, id: \.metadata.id) { version in
                            Text(version.metadata.createdAt, format: .dateTime.day().month().hour().minute().second()).tag(Optional(version.metadata.id))
                        }
                    }.onChange(of: revisionID) { _, _ in values = [:] }
                    Picker(ru ? "Агент" : "Agent", selection: $agentID) {
                        ForEach(agents, id: \.metadata.id) { agent in Text(agent.name).tag(Optional(agent.metadata.id)) }
                    }
                    if agents.isEmpty { Text(ru ? "Назначьте навык агенту в настройках навыка." : "Assign the skill to an agent in its settings.").foregroundStyle(.secondary) }
                }
                if let revision { Section(ru ? "Инструкция" : "Instructions") { Text(revision.instructions).textSelection(.enabled) } }
                Section(ru ? "Параметры" : "Parameters") {
                    ForEach(parameters, id: \.name) { parameter in
                        TextField(parameter.name + (parameter.required ? " *" : ""), text: Binding(get: { values[parameter.name] ?? "" }, set: { values[parameter.name] = $0 }), axis: .vertical)
                    }
                }
                Section {
                    Button(ru ? "Запустить задачу" : "Run task") { submit(schedule: false) }
                    Button(ru ? "Добавить расписание" : "Schedule") { submit(schedule: true) }
                    Text(ru ? "Выбранная версия и параметры сохранятся в задаче." : "The selected revision and parameters are saved with the task.").font(.caption).foregroundStyle(.secondary)
                }.disabled(agentID == nil || revision == nil)
                if let failure { Text(failure).foregroundStyle(.red) }
            }.formStyle(.grouped).disabled(busy)
            .navigationTitle(skill.name)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Cancel")) { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
        .onAppear {
            revisionID = skill.activeRevisionId
            agentID = agents.first { $0.metadata.id == store.selectedAgentID }?.metadata.id ?? agents.first?.metadata.id
        }
    }
    private func submit(schedule: Bool) {
        guard !busy, let commands = store.skillCommands, let agentID, let revision else { return }
        busy = true; failure = nil
        _Concurrency.Task {
            defer { busy = false }
            do {
                if schedule {
                    let goal = try await commands.renderSkill(revision.metadata.id, values: values)
                    try await store.refreshSkills()
                    dismiss(); store.navigate(.createSchedule)
                    store.form.schedule = WorkspaceScheduleForm()
                    store.form.schedule.name = skill.name; store.form.schedule.goal = goal
                    store.form.schedule.skillRevisionID = revision.metadata.id; store.form.schedule.agentID = agentID
                    store.form.schedule.deviceID = store.snapshot.localDeviceID
                } else {
                    let chat = store.currentConversation
                    let isMember = store.snapshot.participants?.contains { $0.conversationId == chat?.metadata.id && $0.kind == .agent && $0.participantId == agentID && !$0.removed } ?? false
                    let chatID = (chat?.kind == .group ? isMember : chat?.agentId == agentID) ? chat?.metadata.id : nil
                    let id = try await commands.runSkill(skill.metadata.id, revisionID: revision.metadata.id, agentID: agentID, values: values, conversationID: chatID)
                    try await store.refreshSkills(taskID: id); dismiss()
                }
            } catch { failure = WorkspaceSkillFailure.text(error, russian: ru) }
        }
    }
}
