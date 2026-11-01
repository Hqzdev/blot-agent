import BlotDesign
import SwiftUI

struct AssistantsLibraryView: View {
    @Environment(AppState.self) private var app
    @State private var creating = false
    @State private var editing: AssistantProfile?
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: KSpace.xl) {
                PageHeader(title: "GPTs", subtitle: "Create assistants with instructions for the way you work.") {
                    KButton(title: "Create GPT", icon: "plus") { creating = true }
                }
                if app.workspaceLibrary.assistants.isEmpty {
                    EmptyState(icon: "cube", title: "Your own assistants",
                                       detail: "Give an assistant a name and instructions, then start a conversation.")
                } else {
                    SettingsGroup(title: "Your GPTs") {
                        ForEach(Array(app.workspaceLibrary.assistants.enumerated()), id: \.element.id) { index, assistant in
                            if index > 0 { SettingsDivider() }
                            ListRow(title: assistant.name, subtitle: assistant.instructions,
                                    action: { app.openAssistantChat(assistant) }) {
                                IconTile(icon: "cube")
                            } trailing: {
                                KButton(title: "Start chat", icon: "message-square", kind: .ghost, height: 28) {
                                    app.openAssistantChat(assistant)
                                }
                                MoreMenu(help: "Actions for \(assistant.name)") {[
                                    .button("Edit…", icon: "pencil") { editing = assistant },
                                    .divider,
                                    .button("Remove", icon: "trash-2", destructive: true) {
                                        app.workspaceLibrary.removeAssistant(assistant.id)
                                    },
                                ]}
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $creating) { AssistantEditorView { app.workspaceLibrary.saveAssistant($0) } }
        .sheet(item: $editing) { assistant in
            AssistantEditorView(assistant: assistant) { app.workspaceLibrary.saveAssistant($0) }
        }
    }
}

private struct AssistantEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let assistant: AssistantProfile?
    let save: (AssistantProfile) -> Void
    @State private var name: String
    @State private var instructions: String
    init(assistant: AssistantProfile? = nil, save: @escaping (AssistantProfile) -> Void) {
        self.assistant = assistant
        self.save = save
        _name = State(initialValue: assistant?.name ?? "")
        _instructions = State(initialValue: assistant?.instructions ?? "")
    }
    var body: some View {
        KSheet(assistant == nil ? "Create GPT" : "Edit GPT",
               subtitle: "Give the assistant a name and instructions. Chats with it are stored like any other chat.", width: 560) {
            KTextField("Name", text: $name, placeholder: "Writing coach", required: true, autofocus: assistant == nil)
            KTextArea("Instructions", text: $instructions, placeholder: "How should this assistant respond?",
                      minHeight: 200, maxHeight: 320)
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            KButton(title: "Save", kind: .primary) {
                save(AssistantProfile(id: assistant?.id ?? UUID(), name: trimmedName, instructions: trimmedInstructions))
                dismiss()
            }.disabled(trimmedName.isEmpty || trimmedInstructions.isEmpty).keyboardShortcut(.defaultAction)
        }
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedInstructions: String { instructions.trimmingCharacters(in: .whitespacesAndNewlines) }
}
