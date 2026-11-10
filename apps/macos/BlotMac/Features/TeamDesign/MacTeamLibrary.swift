import BlotDesign
import SwiftUI

struct MacTeamLibrary: View {
    let destination: MacTeamDestination
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var filter = "Все"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    MacTeamSectionHeading(title: destination.title)
                    BlotIconButton("Добавить", symbol: "plus", size: BlotIconSize.inline, action: add).buttonStyle(WorkspaceButtonStyle())
                }
                switch destination {
                case .routines: routines
                case .skills: skills
                case .memory: memories
                case .files: files
                default: EmptyView()
                }
            }.kAnimation(KMotion.standard, value: filter)
                .kAnimation(KMotion.standard, value: presentation.routines.map(\.id))
                .kAnimation(KMotion.standard, value: presentation.demo.state.skills.map(\.id))
                .kAnimation(KMotion.standard, value: presentation.demo.state.memories.map(\.id))
                .kAnimation(KMotion.standard, value: presentation.demo.state.documents.map(\.id))
                .padding(30).frame(maxWidth: 940).frame(maxWidth: .infinity)
        }.contentMargins(.top, 64, for: .scrollContent)
    }
    private var routines: some View {
        VStack(spacing: 14) {
            Text("В демо расписания выполняются, пока приложение открыто. Для проверки можно запустить задачу сейчас.")
                .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(presentation.routines) { routine in
                HStack(alignment: .top, spacing: 14) {
                    MacTeamAvatar(agent: presentation.agent(for: routine.agentID), size: 36)
                    Button {
                        presentation.sheet = .routine(routine.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(routine.title).font(.system(size: 14, weight: .medium))
                            Text(routine.schedule).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(routine.instructions).font(.system(size: 12)).lineLimit(2).foregroundStyle(.secondary)
                            if let last = routine.lastRun {
                                Text("Последний запуск: " + presentation.dateLabel(last)).font(
                                    .system(size: 10)
                                ).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(BlotPlainButtonStyle())
                    Button("Запустить") { presentation.runRoutine(routine.id) }.buttonStyle(
                        WorkspaceButtonStyle(.secondary))
                    Toggle(
                        "Активно",
                        isOn: Binding(
                            get: { routine.enabled },
                            set: { value in
                                var routine = routine
                                routine.enabled = value
                                presentation.demo.saveRoutine(routine)
                            })
                    ).toggleStyle(MacTeamSwitchStyle(showsLabel: false)).accessibilityLabel(
                        "Расписание «\(routine.title)» активно")
                }.teamCard(padding: 18)
            }
        }
    }
    private var skills: some View {
        VStack(spacing: 12) {
            ForEach(presentation.demo.state.skills) { skill in
                HStack(spacing: 14) {
                    BlotIcon(symbol: "shippingbox", size: BlotIconSize.prominent).foregroundStyle(WorkspaceStyle.ink)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(skill.title).font(.system(size: 13, weight: .medium))
                        Text(presentation.agent(for: skill.agentID).name).font(.system(size: 11)).foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                    Button("Изменить") { presentation.editSkill(skill.id) }.buttonStyle(
                        WorkspaceButtonStyle(.secondary))
                    Button("Использовать") {
                        presentation.open(.agent(skill.agentID))
                        presentation.send("/" + skill.title)
                    }.buttonStyle(WorkspaceButtonStyle())
                }.teamCard()
            }
            if presentation.demo.state.skills.isEmpty {
                ContentUnavailableView {
                    BlotLabel("Пока нет навыков", symbol: "shippingbox", size: BlotIconSize.illustration)
                } description: { Text("Добавьте инструкции для повторяющейся задачи.") }
            }
        }
    }
    private var memories: some View {
        VStack(alignment: .leading, spacing: 14) {
            MacTeamSegmentedControl(title: "Область памяти", options: ["Все", "Общие", "Агента"], selection: $filter)
                .frame(width: 280)
            ForEach(
                presentation.demo.state.memories.filter {
                    filter == "Все" || (filter == "Общие" ? $0.agentID == nil : $0.agentID == presentation.agent.id)
                }
            ) { memory in
                Button {
                    presentation.editMemory(memory.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(memory.text).font(.system(size: 13))
                            Text(memory.agentID.map { presentation.agent(for: $0).name } ?? "Общая память").font(
                                .system(size: 11)
                            ).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BlotIcon(symbol: "pencil", size: BlotIconSize.control).foregroundStyle(WorkspaceStyle.ink)
                    }.frame(maxWidth: .infinity, alignment: .leading).teamCard()
                }.buttonStyle(BlotPlainButtonStyle())
            }
        }
    }
    private var files: some View {
        VStack(spacing: 12) {
            ForEach(presentation.demo.state.documents) { document in
                MacTeamNavigationButton {
                    presentation.showDocument(document.id)
                } label: {
                    HStack(spacing: 12) {
                        MacTeamFileIcon(filename: document.title)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(document.title).font(.system(size: 13, weight: .medium))
                            Text(
                                presentation.agent(for: document.agentID).name
                                    + (document.published ? " · Сохранён в рассылках" : " · " + MacTeamFileKind(filename: document.title).title)
                            ).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BlotIcon(symbol: "arrow.up.right", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                    }
                }
            }
        }
    }
    private func add() {
        switch destination {
        case .routines: presentation.sheet = .routine(nil)
        case .skills: presentation.editSkill()
        case .memory: presentation.editMemory()
        default:
            let doc = MacDemoDocument(
                id: UUID().uuidString, title: "Новый документ.md", body: "", agentID: presentation.agent.id)
            presentation.demo.update { $0.documents.append(doc) }
            presentation.showDocument(doc.id)
        }
    }
}

struct MacTeamItemEditor: View {
    let kind: MacTeamDestination
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var scope = ""
    @State private var confirmDelete = false
    private var editingID: String? { kind == .memory ? presentation.editingMemoryID : presentation.editingSkillID }
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: kind == .memory ? "Память агента" : "Навык агента")
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                if kind == .skills { TextField("Название навыка", text: $title) }
                WorkspaceLocalizedText(kind == .memory ? "Что нужно запомнить?" : "Инструкции и шаги").fontWeight(.medium)
                TextEditor(text: $text).font(.system(size: 13)).frame(height: 180).scrollContentBackground(.hidden)
                    .padding(10).background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: 14))
                MacTeamSelect(
                    title: kind == .memory ? "Область" : "Агент", selection: $scope,
                    options: (kind == .memory ? [MacTeamOption("Общая память", "")] : [])
                        + presentation.agents.map { .init($0.name, $0.id) })
                Text(
                    kind == .memory
                        ? "Общая память доступна всем агентам. Личные предпочтения относятся к выбранному специалисту."
                        : "Навык появится в меню / и будет доступен для повторного запуска без записи экрана."
                )
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.font(.system(size: 12)).padding(24)
            Divider()
            HStack {
                if editingID != nil {
                    Button("Удалить", role: .destructive) { confirmDelete = true }.buttonStyle(BlotPlainButtonStyle())
                }
                Spacer()
                Button("Отмена") { dismiss() }.buttonStyle(WorkspaceButtonStyle(.secondary))
                Button("Сохранить", action: save).buttonStyle(WorkspaceButtonStyle()).disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == .skills && title.isEmpty))
            }.padding(18)
        }.frame(width: 550)
            .onAppear {
                if kind == .memory, let item = presentation.demo.state.memories.first(where: { $0.id == editingID }) {
                    text = item.text
                    scope = item.agentID ?? ""
                } else if kind == .skills,
                    let item = presentation.demo.state.skills.first(where: { $0.id == editingID })
                {
                    title = item.title
                    text = item.instructions
                    scope = item.agentID
                } else {
                    scope = kind == .memory ? "" : presentation.agent.id
                }
            }
            .onDisappear {
                presentation.editingMemoryID = nil
                presentation.editingSkillID = nil
            }
            .confirmationDialog("Удалить запись из демо?", isPresented: $confirmDelete) {
                Button("Удалить", role: .destructive) {
                    let id = editingID
                    presentation.demo.update { state in
                        if kind == .memory {
                            state.memories.removeAll { $0.id == id }
                        } else {
                            state.skills.removeAll { $0.id == id }
                        }
                    }
                    dismiss()
                }
            }
    }
    private func save() {
        let id = editingID ?? UUID().uuidString
        presentation.demo.update { state in
            if kind == .memory {
                let item = MacDemoMemory(id: id, text: text, agentID: scope.isEmpty ? nil : scope)
                if let index = state.memories.firstIndex(where: { $0.id == id }) {
                    state.memories[index] = item
                } else {
                    state.memories.append(item)
                }
            } else {
                let item = MacDemoSkill(id: id, title: title, instructions: text, agentID: scope)
                if let index = state.skills.firstIndex(where: { $0.id == id }) {
                    state.skills[index] = item
                } else {
                    state.skills.append(item)
                }
            }
        }
        dismiss()
    }
}
