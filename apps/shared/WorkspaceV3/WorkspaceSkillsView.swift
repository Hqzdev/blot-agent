import BlotDomain
import BlotWorkspace
import SwiftUI

private struct SkillSelection: Identifiable {
    let id = UUID()
    let skill: BlotV3.Skill?
}

struct WorkspaceSkillsView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var search = ""
    @State private var archived = false
    @State private var editor: SkillSelection?
    @State private var runner: SkillSelection?
    private var ru: Bool { store.language == "ru" }
    private var skills: [BlotV3.Skill] {
        (store.snapshot.skills ?? []).filter { $0.archived == archived && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(ru ? "Навыки" : "Skills").font(.largeTitle.bold())
                Spacer()
                Button { editor = .init(skill: nil) } label: { Label(ru ? "Создать" : "Create", systemImage: "plus") }
                    .disabled(store.skillCommands == nil)
            }
            TextField(ru ? "Найти навык" : "Find a skill", text: $search).textFieldStyle(.roundedBorder)
            Toggle(ru ? "Архив" : "Archive", isOn: $archived).toggleStyle(.switch)
            if skills.isEmpty { Text(ru ? "Здесь появятся сохранённые инструкции с параметрами для ваших агентов." : "Saved instructions with parameters for your agents will appear here.").foregroundStyle(.secondary) }
            ForEach(skills, id: \.metadata.id) { skill in
                WorkspaceCard {
                    Label(skill.name, systemImage: "shippingbox").font(.headline).foregroundStyle(.purple)
                    if let revision = store.snapshot.skillRevisions?.first(where: { $0.metadata.id == skill.activeRevisionId }) {
                        Text(revision.instructions).lineLimit(3).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(ru ? "Изменить" : "Edit") { editor = .init(skill: skill) }
                        if !skill.archived { Button(ru ? "Запустить" : "Run") { runner = .init(skill: skill) } }
                    }.buttonStyle(.bordered)
                }
            }
        }
        .sheet(item: $editor) { selection in WorkspaceSkillEditor(skill: selection.skill).environment(store) }
        .sheet(item: $runner) { selection in
            if let skill = selection.skill { WorkspaceSkillRunner(skill: skill).environment(store) }
        }
    }
}

struct WorkspaceSkillEditor: View {
    let skill: BlotV3.Skill?
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var instructions = ""
    @State private var parameters: [SkillParameter] = []
    @State private var tools: Set<String> = []
    @State private var busy = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var revisions: [BlotV3.SkillRevision] {
        (store.snapshot.skillRevisions ?? []).filter { $0.skillId == skill?.metadata.id }.sorted { $0.metadata.createdAt > $1.metadata.createdAt }
    }
    private var availableTools: [String] {
        Set((store.snapshot.configurations ?? []).flatMap(\.toolIds)).union(tools).sorted()
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(ru ? "Инструкция" : "Instructions") {
                    TextField(ru ? "Название" : "Name", text: $name)
                    TextEditor(text: $instructions).frame(minHeight: 150)
                    Text(ru ? "Для подстановки используйте {{parameter}}. Значения задаются при запуске." : "Use {{parameter}} for values supplied when running.").font(.caption).foregroundStyle(.secondary)
                }
                Section(ru ? "Параметры" : "Parameters") {
                    ForEach(parameters.indices, id: \.self) { index in
                        HStack {
                            TextField("parameter", text: Binding(get: { parameters[index].name }, set: { parameters[index] = .init(name: $0, required: parameters[index].required) }))
                            Toggle(ru ? "Обязательный" : "Required", isOn: Binding(get: { parameters[index].required }, set: { parameters[index] = .init(name: parameters[index].name, required: $0) }))
                            Button(role: .destructive) { parameters.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    Button(ru ? "Добавить параметр" : "Add parameter") { parameters.append(.init(name: "")) }.disabled(parameters.count >= 32)
                }
                Section(ru ? "Инструменты" : "Tools") {
                    Text(ru ? "Выберите нужные инструменты. Для приложений включается поиск доступных ресурсов. Назначение навыка не выдаёт новых прав." : "Choose the tools the skill needs. App tools include resource discovery. Assigning a skill does not grant new permissions.").font(.caption).foregroundStyle(.secondary)
                    ForEach(availableTools, id: \.self) { tool in
                        Toggle(WorkspaceSkillToolCatalog.title(tool, russian: ru), isOn: Binding(get: { tools.contains(tool) }, set: { if $0 { tools.insert(tool) } else { tools.remove(tool) } }))
                    }
                }
                if let skill {
                    Section(ru ? "Агенты" : "Agents") {
                        ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                            let assignment = store.snapshot.skillAssignments?.first { $0.skillID == skill.metadata.id && $0.agentID == agent.metadata.id }
                            Toggle(agent.name, isOn: Binding(get: { assignment?.assigned == true }, set: { selected in
                                perform(close: false) { commands in try await commands.assignSkill(skill.metadata.id, agentID: agent.metadata.id, assigned: selected, version: assignment?.version ?? 0) }
                            })).disabled(skill.archived)
                        }
                    }
                    Section(ru ? "История версий" : "Version history") {
                        ForEach(revisions, id: \.metadata.id) { revision in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(revision.metadata.createdAt, format: .dateTime.day().month().year().hour().minute().second()).font(.caption)
                                Text(revision.instructions).lineLimit(2)
                                if revision.metadata.id == skill.activeRevisionId { Text(ru ? "Активная версия" : "Active revision").foregroundStyle(.purple) }
                                else { Button(ru ? "Сделать активной" : "Make active") { perform { try await $0.activateSkill(skill, revisionID: revision.metadata.id) } } }
                            }
                        }
                    }
                    Section {
                        Button(ru ? (skill.archived ? "Восстановить из архива" : "Архивировать") : (skill.archived ? "Restore from archive" : "Archive")) {
                            perform { try await $0.archiveSkill(skill, archived: !skill.archived) }
                        }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.formStyle(.grouped).disabled(busy)
            .navigationTitle(ru ? "Настройка навыка" : "Skill settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Cancel")) { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Save")) { perform { commands in
                        _ = try await commands.saveSkill(id: skill?.metadata.id, version: skill?.metadata.version ?? 0, name: name,
                            instructions: instructions, parameters: parameters, tools: tools.sorted())
                    } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.interactiveDismissDisabled(busy)
        #if os(macOS)
        .frame(width: 620, height: 720)
        #endif
        .onAppear {
            name = skill?.name ?? ""
            if let revision = revisions.first(where: { $0.metadata.id == skill?.activeRevisionId }) {
                instructions = revision.instructions; parameters = (try? WorkspaceSkillService.parameters(revision)) ?? []; tools = Set(revision.toolIds)
            }
        }
    }
    private func perform(close: Bool = true, _ action: @escaping @MainActor (any WorkspaceSkillCommands) async throws -> Void) {
        guard !busy, let commands = store.skillCommands else { return }
        busy = true; failure = nil
        _Concurrency.Task {
            defer { busy = false }
            do { try await action(commands); try await store.refreshSkills(); if close { dismiss() } }
            catch { failure = WorkspaceSkillFailure.text(error, russian: ru) }
        }
    }
}
