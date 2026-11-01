import BlotAPI
import BlotDesign
import SwiftUI

struct SkillEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: WorkspaceRow?
    @State private var name: String
    @State private var instruction: String
    @State private var project: String
    @State private var roles: Set<String>
    @State private var availableRoles: [String] = []
    @State private var enabled: Bool
    @State private var error: String?
    private var key: String { "skill.editor:" + (item?.id.uuidString ?? "new") }
    init(item: WorkspaceRow? = nil) {
        self.item = item
        _name = State(initialValue: item?.data.text("name") ?? "")
        _instruction = State(initialValue: item?.data.text("instruction") ?? "")
        _project = State(initialValue: item?.projectId?.uuidString ?? "")
        _roles = State(initialValue: Set(item?.data.strings("roles") ?? []))
        _enabled = State(initialValue: item?.data.flag("enabled") ?? true)
    }
    var body: some View {
        let saving = app.workspace.commands.active.contains(key)
        let retrying = app.workspace.commands.pending[key] != nil && !saving
        KSheet(item == nil ? "New skill" : "Edit skill",
               subtitle: "Skills give specialists an instruction. They never grant tool permissions.", width: 620) {
            VStack(alignment: .leading, spacing: KSpace.lg) {
                HStack(alignment: .top, spacing: KSpace.md) {
                    KTextField("Name", text: $name, placeholder: "Release notes in my voice", required: true,
                               autofocus: item == nil)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Available in").font(KFont.caption(.medium)).foregroundStyle(K.text2)
                        ChoiceMenu(selection: $project,
                                   options: [ChoiceOption(id: "", title: "All projects")]
                                       + app.projects.map { ChoiceOption(id: $0.id, title: $0.name) },
                                   accessibilityTitle: "Available in")
                            .disabled(item != nil)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Roles").font(KFont.caption(.medium)).foregroundStyle(K.text2)
                    if availableRoles.isEmpty && error == nil {
                        HStack(spacing: KSpace.sm) {
                            ProgressView().controlSize(.mini)
                            Text("Loading roles…").font(KFont.caption()).foregroundStyle(K.text3)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6, alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(availableRoles, id: \.self) { role in
                            KToggleChip(title: AgentRole.displayName(role), isOn: Binding(
                                get: { roles.contains(role) },
                                set: { if $0 { roles.insert(role) } else { roles.remove(role) } }))
                        }
                    }
                }
                KTextArea("Instruction", text: $instruction, placeholder: "How should the specialist work?",
                          mono: true, minHeight: 200, maxHeight: 280)
                HStack(spacing: KSpace.md) {
                    KToggle(isOn: $enabled).accessibilityLabel("Enabled for new sessions")
                    Text("Enabled for new sessions").font(KFont.ui(13)).foregroundStyle(K.text)
                    Spacer()
                }
            }
            .disabled(app.workspace.commands.pending[key] != nil)
            if retrying {
                InlineFeedback(text: "The server has not confirmed the last save. Send it again unchanged.", tone: .warning)
            }
            if let error { InlineFeedback(text: error, tone: .error) }
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            KButton(title: retrying ? "Send save again" : "Save", kind: .primary, loading: saving) { save() }
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || roles.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .task {
            do {
                let rows = try await BackendRuntime.shared.client.get("v2/roles", as: [BackendJSON].self)
                availableRoles = rows.map { $0.text("role") }.sorted()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        let data = BackendJSON.object([
            "name": .string(name), "instruction": .string(instruction),
            "roles": .array(roles.sorted().map(BackendJSON.string)), "enabled": .bool(enabled),
        ])
        let payload = BackendJSON.object([
            "id": item.map { .string($0.id.uuidString) } ?? .null, "data": data,
        ])
        Task {
            do {
                let receipt = try await app.workspace.send(
                    "skill.save", payload: payload, row: item, projectID: UUID(uuidString: project), key: key)
                app.skills.selectedID = receipt.operationId
                app.toasts.show(item == nil ? "Skill created" : "Skill saved")
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
