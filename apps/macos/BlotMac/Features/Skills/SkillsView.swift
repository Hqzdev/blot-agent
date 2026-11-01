import BlotAPI
import BlotDesign
import SwiftUI

struct SkillsView: View {
    @Environment(AppState.self) private var app
    @State private var creating = false
    var body: some View {
        Group {
            if let row = app.workspace.find("SKILL", app.skills.selectedID) {
                PageContent { SkillDetailView(item: row).id(row.id).transition(.kAppear) }
            } else if app.workspace.loading {
                ContentSkeleton()
            } else {
                EmptyState(icon: "puzzle",
                           title: app.workspace.rows("SKILL").isEmpty ? "No skills yet" : "Choose a skill",
                           detail: "A skill is a versioned instruction for chosen specialists. It never grants tool permissions.",
                           actionTitle: "New skill", actionIcon: "plus") { creating = true }
                    .frame(maxHeight: .infinity)
            }
        }
        .kAnimation(value: app.skills.selectedID)
        .sheet(isPresented: $creating) { SkillEditorView() }
    }
}

extension AppState {
    /// Turns a skill on or off with the same `skill.save` command the editor uses.
    func setSkill(_ item: WorkspaceRow, enabled: Bool) {
        var fields: [String: BackendJSON] = [:]
        if case .object(let data) = item.data { fields = data }
        fields["enabled"] = .bool(enabled)
        let payload = BackendJSON.object(["id": .string(item.id.uuidString), "data": .object(fields)])
        Task {
            do {
                try await workspace.send("skill.save", payload: payload, row: item, key: "skill.toggle:" + item.id.uuidString)
            } catch {
                toasts.show("Couldn't turn \(enabled ? "on" : "off") the skill. \(error.localizedDescription)", tone: .error)
            }
        }
    }
}
