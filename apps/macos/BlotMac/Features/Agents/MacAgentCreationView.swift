import BlotDesign
import SwiftUI

struct MacAgentCreationView: View {
    var isEditing = false
    @Environment(WorkspaceStore.self) private var store
    @FocusState private var nameFocused: Bool
    private let colors = ["brown", "red", "orange", "amber", "green", "teal", "blue", "purple", "pink", "gray"]
    private let shapes: [WorkspaceAvatar.ShapeKind] = [.round, .oval, .square, .pill, .triangle, .hexagon, .cloud, .drop, .tall, .star]

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    editor.padding(.top, max(32, geometry.size.height * 0.11))
                    WorkspaceFeedback().font(MacWorkspaceStyle.caption).padding(.top, 12)
                    if !isEditing { suggestions.padding(.top, max(48, geometry.size.height * 0.10)) }
                }.padding(.horizontal, 28).padding(.bottom, 24).frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.basedOnSize)
        }
        .task { nameFocused = true }
    }

    private var editor: some View {
        @Bindable var store = store
        return VStack(spacing: 22) {
            ZStack {
                WorkspaceAvatar(shape: .init(rawValue: store.form.agent.shape) ?? .round,
                    color: WorkspaceAvatarView.color(store.form.agent.color), size: 86)
                    .id(store.form.agent.shape + store.form.agent.color)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }.frame(height: 96).animation(.easeInOut(duration: 0.18), value: store.form.agent.shape + store.form.agent.color)
            HStack(spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Button { store.form.agent.color = color } label: {
                        Circle().fill(WorkspaceAvatarView.color(color)).frame(width: 24, height: 24)
                            .padding(3).overlay(Circle().strokeBorder(store.form.agent.color == color ? Color.accentColor : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityLabel(store.t(color))
                        .accessibilityAddTraits(store.form.agent.color == color ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                ForEach(shapes, id: \.self) { shape in
                    Button { store.form.agent.shape = shape.rawValue } label: {
                        WorkspaceAvatar(shape: shape, color: WorkspaceAvatarView.color(store.form.agent.color), size: 28)
                            .frame(width: 34, height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(store.form.agent.shape == shape.rawValue ? Color.accentColor : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityLabel(store.t(shape.rawValue))
                        .accessibilityAddTraits(store.form.agent.shape == shape.rawValue ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(store.t("Name")).font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary)
                TextField(store.t("New agent"), text: $store.form.agent.name)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($nameFocused)
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(BlotColor.edge))
                    .accessibilityLabel(store.t("Name"))
                    .onSubmit { save() }
            }.padding(.top, 10)
            WorkspaceAgentRuntimeOptions()
            DisclosureGroup(store.t("Instructions")) {
                TextField(store.t("What it does"), text: $store.form.agent.instructions, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(3...6).font(MacWorkspaceStyle.body)
                    .padding(10).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }.font(MacWorkspaceStyle.caption).foregroundStyle(WorkspaceStyle.secondary)
            Button(action: save) {
                HStack(spacing: 7) {
                    if store.busy { ProgressView().controlSize(.mini) }
                    Text(store.t(isEditing ? "Save agent" : "Get started"))
                }.font(.system(size: 14)).padding(.horizontal, 14).frame(height: 36)
                    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(store.busy || store.form.agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(store.form.agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }.frame(maxWidth: 414).frame(maxWidth: .infinity)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t("Suggestions")).font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(MacAgentTemplate.all) { template in
                        Button {
                            store.form.agent.name = store.t(template.name)
                            store.form.agent.instructions = store.t(template.instructions)
                            store.form.agent.shape = template.shape.rawValue
                            store.form.agent.color = template.color
                            nameFocused = true
                        } label: {
                            HStack(spacing: 16) {
                                WorkspaceAvatar(shape: template.shape, color: WorkspaceAvatarView.color(template.color), size: 52)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(store.t(template.name)).font(.system(size: 17, weight: .medium))
                                    Text(store.t(template.summary)).font(.system(size: 14)).foregroundStyle(WorkspaceStyle.secondary)
                                        .multilineTextAlignment(.leading).lineLimit(3)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(22).frame(width: 330, height: 140)
                                .overlay(RoundedRectangle(cornerRadius: BlotRadius.panel).strokeBorder(MacWorkspaceStyle.edge))
                                .contentShape(RoundedRectangle(cornerRadius: BlotRadius.panel))
                        }.buttonStyle(.plain).disabled(store.busy)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private func save() {
        guard !store.busy, !store.form.agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _Concurrency.Task {
            if isEditing { await store.perform(.saveAgent, next: .agentProfile) }
            else { await store.createDesktopAgentAndStartChat() }
        }
    }
}
