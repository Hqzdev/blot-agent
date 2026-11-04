import BlotDesign
import SwiftUI

struct MacTeamAgentEditor: View {
    let isNew: Bool
    let agentID: String?
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @State private var agent = MacDemoSeed.make().agents[0]
    @AppStorage(MacTeamPreferenceKey.defaultRole) private var defaultRole = "Ассистент"
    @AppStorage(MacTeamPreferenceKey.defaultInstructions) private var defaultInstructions = ""
    private let colors = ["purple", "red", "orange", "amber", "green", "teal", "blue", "pink", "brown", "gray"]

    init(isNew: Bool, agentID: String? = nil) {
        self.isNew = isNew
        self.agentID = agentID
    }

    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: isNew ? "Новый агент" : "Профиль агента")
            Divider()
            HStack(alignment: .top, spacing: 30) {
                appearance.frame(width: 240)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        field("Имя") { TextField("Как зовут агента?", text: $agent.name) }
                        field("Роль") { TextField("Например, исполнительный ассистент", text: $agent.role) }
                        field("Инструкции") {
                            TextEditor(text: $agent.instructions).font(.system(size: 13)).frame(height: 132)
                                .scrollContentBackground(.hidden).padding(7)
                                .background(WorkspaceStyle.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                        }
                        Toggle(isOn: $agent.notifications) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Уведомления").font(.system(size: 12, weight: .medium))
                                Text("Когда работа готова или нужно ваше решение").font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }.toggleStyle(MacTeamSwitchStyle()).controlSize(.small)
                        if isNew {
                            Divider()
                            Text("Что поручим агенту?").font(.system(size: 12, weight: .medium))
                            ForEach(
                                [
                                    "Почта и календарь", "Исследования и мониторинг", "Тексты и рассылки",
                                    "Финансы и счета",
                                ], id: \.self
                            ) { role in
                                Button {
                                    agent.role = role
                                    agent.instructions = [defaultInstructions,
                                        "Помогай с задачами по направлению «\(role.lowercased())». Уточняй недостающие данные и согласовывай действия со мной."
                                    ].filter { !$0.isEmpty }.joined(separator: "\n\n")
                                } label: {
                                    HStack {
                                        Text(role)
                                        Spacer()
                                        BlotIcon(symbol: "arrow.up.left", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                                    }.font(.system(size: 12)).padding(10).background(
                                        WorkspaceStyle.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(BlotPlainButtonStyle())
                            }
                        }
                    }.padding(.bottom, 8)
                }
            }.padding(24)
            Divider()
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.buttonStyle(WorkspaceButtonStyle(.secondary))
                Button(isNew ? "Создать агента" : "Сохранить") {
                    presentation.saveAgent(agent, openConversation: agentID == nil)
                }.buttonStyle(
                    WorkspaceButtonStyle()
                ).disabled(agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(18)
        }.frame(width: 760, height: isNew ? 690 : 590)
            .onAppear {
                agent =
                    isNew
                    ? MacTeamAgent(
                        id: UUID().uuidString, name: "", role: defaultRole.isEmpty ? "Ассистент" : defaultRole,
                        instructions: defaultInstructions, color: "teal",
                        shape: .round, preview: "С чего начнём?")
                    : agentID.map { presentation.agent(for: $0) } ?? presentation.agent

            }
    }
    private var appearance: some View {
        VStack(spacing: 16) {
            ZStack {
                MacTeamAvatar(agent: agent, size: 104).id(agent.avatarShape).transition(.opacity)
            }.padding(.vertical, 4)
                .kAnimation(KMotion.standard, value: agent.avatarShape)
                .kAnimation(KMotion.standard, value: agent.color)
            avatarOptions
            Spacer(minLength: 0)
        }
    }
    private var avatarOptions: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                ForEach(WorkspaceAvatar.ShapeKind.allCases, id: \.self) { shape in
                    Button {
                        agent.shape = shape
                        agent.avatarData = nil
                    } label: {
                        WorkspaceAvatar(shape: shape, color: WorkspaceAvatarView.color(agent.color), size: 31)
                            .padding(4).background(
                                agent.shape == shape ? WorkspaceStyle.surface : .clear,
                                in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(BlotPlainButtonStyle()).help(shape.rawValue).accessibilityLabel("Форма \(shape.rawValue)")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                ForEach(colors, id: \.self) { color in
                    Button {
                        agent.color = color
                        agent.avatarData = nil
                    } label: {
                        Circle().fill(WorkspaceAvatarView.color(color)).frame(width: 22, height: 22).padding(3)
                            .overlay(
                                Circle().strokeBorder(
                                    agent.color == color ? Color.primary.opacity(0.5) : .clear, lineWidth: 1))
                    }.buttonStyle(BlotPlainButtonStyle()).help(color).accessibilityLabel("Цвет \(color)")
                }
            }
        }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content()
        }.textFieldStyle(MacTeamTextFieldStyle())
    }
}

struct MacTeamGroupEditor: View {
    let groupID: String?
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var name = "Заказы и финансы"
    @State private var selected: Set<String> = ["inbox", "finance", "support"]
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: groupID == nil ? "Новый групповой чат" : "Участники группы")
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                Text("Агенты работают вместе").font(.system(size: 23, weight: .medium))
                Text("Соберите специалистов в одном разговоре, чтобы видеть общий контекст и передачу задач.")
                    .foregroundStyle(.secondary).lineSpacing(4)
                TextField("Название группы", text: $name).textFieldStyle(MacTeamTextFieldStyle())
                ForEach(presentation.agents) { agent in
                    Toggle(
                        isOn: Binding(
                            get: { selected.contains(agent.id) },
                            set: { if $0 { selected.insert(agent.id) } else { selected.remove(agent.id) } })
                    ) {
                        HStack(spacing: 10) {
                            MacTeamAvatar(agent: agent, size: 30)
                            Text(agent.name)
                            Text(agent.role).foregroundStyle(.secondary).font(.system(size: 11))
                        }
                    }.toggleStyle(MacTeamCheckboxStyle()).padding(.vertical, 3)
                }
            }.padding(24)
            Divider()
            HStack {
                Text("Участников: \(selected.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(groupID == nil ? "Создать чат" : "Сохранить") {
                    if let id = presentation.demo.saveGroup(id: groupID, name: name, agentIDs: Array(selected)) {
                        presentation.open(.group(id))
                        presentation.sheet = nil
                    }
                }.buttonStyle(WorkspaceButtonStyle()).disabled(
                    selected.count < 2 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(18)
        }.frame(width: 510)
            .onAppear {
                if let group = presentation.demo.state.groups.first(where: { $0.id == groupID }) {
                    name = group.name
                    selected = Set(group.agentIDs)
                } else {
                    name = "Новая группа"
                    selected = [presentation.agent.id]
                }
            }
    }
}
