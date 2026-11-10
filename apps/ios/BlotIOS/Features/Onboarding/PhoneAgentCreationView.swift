import BlotDesign
import SwiftUI

struct PhoneAgentCreationView: View {
    var isEditing = false
    @Environment(WorkspaceStore.self) private var store
    @FocusState private var roleFocused: Bool

    var body: some View {
        @Bindable var store = store
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    TextField(store.t("Give your agent a role"), text: $store.form.agent.name)
                        .font(.body.weight(.medium)).multilineTextAlignment(.center)
                        .textFieldStyle(.plain).textInputAutocapitalization(.words)
                        .focused($roleFocused)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(WorkspaceStyle.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: PhonePageLayout.radius))
                        .accessibilityLabel(store.t("Agent role"))
                        .padding(.bottom, PhonePageLayout.sectionSpacing)
                    VStack(spacing: PhonePageLayout.sectionSpacing) {
                        PhoneAgentPreview(shape: .init(rawValue: store.form.agent.shape) ?? .cloud,
                                          color: store.form.agent.color, size: 112)
                        shapePicker
                        colorPicker
                    }.accessibilityElement(children: .contain).accessibilityLabel(store.t("Agent look"))
                    if isEditing {
                        TextField(store.t("What it does"), text: $store.form.agent.instructions, axis: .vertical)
                            .lineLimit(3...8).textFieldStyle(.plain).padding(.top, 24)
                            .accessibilityLabel(store.t("What it does"))
                    }
                    WorkspaceFeedback().padding(.top, 12)
                    Spacer(minLength: 32)
                }
                .padding(PhonePageLayout.inset)
                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 80), alignment: .top)
            }.scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { create() } label: {
                Text(store.t(isEditing ? "Save" : "Create")).font(.headline).frame(maxWidth: .infinity, minHeight: 24)
            }.buttonStyle(WorkspaceButtonStyle()).disabled(store.busy)
                .padding(.horizontal, PhonePageLayout.inset).padding(.vertical, 12)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PhonePageHeader(title: store.t(isEditing ? "Edit agent" : "Create new agent"), back: close)
        }
        .environment(\.phonePageTitle, store.t(isEditing ? "Edit agent" : "Create new agent"))
        .background(WorkspaceStyle.canvas.ignoresSafeArea())
        .task { if !isEditing { roleFocused = true } }
        .sensoryFeedback(.selection, trigger: store.form.agent.shape)
        .sensoryFeedback(.selection, trigger: store.form.agent.color)
    }

    private var shapePicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(PhoneAgentAppearance.shapes, id: \.self) { shape in
                Button { store.form.agent.shape = shape.rawValue } label: {
                    WorkspaceAvatar(shape: shape, color: WorkspaceAvatarView.color(store.form.agent.color), size: 34, showsEyes: false)
                        .frame(width: 44, height: 44)
                        .background(store.form.agent.shape == shape.rawValue ? WorkspaceStyle.canvas : .clear, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityLabel(store.t(shape.rawValue))
                    .accessibilityAddTraits(store.form.agent.shape == shape.rawValue ? .isSelected : [])
            }
        }.frame(maxWidth: 236)
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 6), spacing: 2) {
            ForEach(PhoneAgentAppearance.colors, id: \.self) { color in
                Button { store.form.agent.color = color } label: {
                    Circle().fill(WorkspaceAvatarView.color(color)).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(WorkspaceStyle.ink.opacity(color == "white" ? 0.08 : 0)))
                        .padding(5)
                        .overlay(Circle().strokeBorder(store.form.agent.color == color ? WorkspaceStyle.secondary.opacity(0.4) : .clear, lineWidth: 2))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(store.t(color))
                    .accessibilityAddTraits(store.form.agent.color == color ? .isSelected : [])
            }
        }.frame(maxWidth: 276)
    }

    private func create() {
        let role = store.form.agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !role.isEmpty else {
            store.error = store.t("Enter a role for your agent.")
            roleFocused = true
            return
        }
        store.form.agent.name = role
        if store.form.agent.instructions.isEmpty {
            store.form.agent.instructions = store.language == "ru"
                ? "Ваша роль: \(role). Помогайте пользователю с задачами по этой роли. Уточняйте недостающие детали и согласовывайте значимые действия."
                : "Your role is \(role). Help the user with work related to this role. Ask for missing details and confirm significant actions."
        }
        _Concurrency.Task {
            if isEditing {
                await store.perform(.saveAgent)
                if store.error == nil { close() }
            } else { await store.createAgentAndStartChat() }
        }
    }

    private func close() {
        if isEditing {
            if store.agentAppearanceVisible { store.agentAppearanceVisible = false }
            else { store.back() }
        }
        else if store.agentCreationVisible { store.agentCreationVisible = false }
        else { store.back() }
    }
}
