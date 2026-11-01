import BlotAPI
import BlotDesign
import SwiftUI

/// «13 · Skills» detail: header with version, when Blot uses the skill, and its instruction.
struct SkillDetailView: View {
    @Environment(AppState.self) private var app
    let item: WorkspaceRow
    @State private var editing = false
    @State private var deleting = false

    private var enabled: Bool { item.data.flag("enabled") }
    private var instruction: String { item.data.text("instruction") }

    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.section) {
            PageHeader(icon: "file-text", title: item.data.text("name"),
                       subtitle: "An instruction for the roles below. It never grants tool permissions; changes apply to new sessions.") {
                Badge(text: "v\(item.version)")
            } actions: {
                KButton(title: "Edit", icon: "pencil") { editing = true }
                MoreMenu(help: "Skill actions") {[
                    .button(enabled ? "Turn off" : "Turn on", icon: enabled ? "pause" : "play") { app.setSkill(item, enabled: !enabled) },
                    .divider,
                    .button("Delete…", icon: "trash-2", destructive: true) { deleting = true },
                ]}
            }

            SettingsGroup(title: "When Blot uses it") {
                SettingsRow(title: "Enabled", detail: "Loaded into new sessions of the roles below.") {
                    KToggle(isOn: Binding(get: { enabled }, set: { app.setSkill(item, enabled: $0) }))
                        .accessibilityLabel("Skill enabled")
                        .disabled(!app.workspace.commands.active.isEmpty)
                }
                SettingsDivider()
                SettingsRow(title: "Projects", detail: "Where this skill is available.") {
                    Chip(icon: "folder",
                         label: item.projectId.flatMap { app.workspace.find("PROJECT", $0)?.data.text("name") } ?? "All projects",
                         chevron: false, bordered: true)
                }
                SettingsDivider()
                SettingsRow(title: "Roles", detail: "Specialists that receive this instruction.") {
                    HStack(spacing: 4) {
                        ForEach(item.data.strings("roles"), id: \.self) { role in
                            Badge(text: AgentRole.displayName(role))
                        }
                    }
                }
            }

            SettingsGroup(title: "Instruction", action: {
                HStack(spacing: KSpace.sm) {
                    Text("\(instruction.split(whereSeparator: \.isWhitespace).count) words")
                        .font(KFont.mono(11)).foregroundStyle(K.text3)
                    CopyButton(text: instruction)
                }
            }) {
                Text(instruction.isEmpty ? " " : instruction)
                    .font(KFont.mono(12)).foregroundStyle(K.text).lineSpacing(5)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(KSpace.lg).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $editing) { SkillEditorView(item: item) }
        .confirmationDialog("Delete “\(item.data.text("name"))”?", isPresented: $deleting) {
            Button("Delete skill", role: .destructive) {
                Task {
                    do {
                        try await app.workspace.send("skill.delete", payload: item.idPayload, row: item)
                        app.toasts.show("Skill deleted")
                    } catch { app.toasts.show("Couldn't delete the skill. \(error.localizedDescription)", tone: .error) }
                }
            }
        } message: {
            Text("New sessions will no longer receive this instruction.")
        }
    }
}
