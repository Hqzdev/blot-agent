import BlotAPI
import BlotDesign
import SwiftUI

/// Settings › Instructions and Skills: instructions are stored as versioned skills.
struct AgentSettingsView: View {
    @Environment(AppState.self) private var app
    @Bindable var settings: SettingsState
    @State private var creating = false
    var body: some View {
        let count = app.workspace.rows("SKILL").count
        SettingsGroup(title: "Agent instructions",
                      detail: "Instructions are saved as versioned skills for chosen roles and projects. They apply to new sessions and never extend tool permissions.") {
            SettingsRow(title: "New instruction", detail: "Write an instruction and choose which specialists receive it.") {
                KButton(title: "Create…", icon: "plus", kind: .primary) { creating = true }
            }
            SettingsDivider()
            SettingsRow(title: "Saved skills", detail: count == 0 ? "None yet" : "\(count) saved on the server") {
                KButton(title: "Open Skills", icon: "puzzle") {
                    app.showingSettings = false
                    app.openSection(.skills)
                }
            }
        }
        .sheet(isPresented: $creating) { SkillEditorView() }
    }
}
