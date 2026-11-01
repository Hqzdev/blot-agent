import BlotAPI
import BlotDesign
import SwiftUI

/// «13 · Skills» sidebar: search, new skill, enabled and disabled skills with toggles.
struct SkillsSidebar: View {
    @Environment(AppState.self) private var app
    @State private var creating = false
    private var rows: [WorkspaceRow] {
        app.workspace.rows("SKILL").filter {
            app.skills.search.isEmpty || $0.data.text("name").localizedCaseInsensitiveContains(app.skills.search)
        }
    }

    var body: some View {
        @Bindable var selection = app.skills
        VStack(spacing: 0) {
            KSearchField(placeholder: "Search skills", text: $selection.search)
                .padding(.horizontal, 12).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    SidebarItem(icon: "plus", label: "New skill") { creating = true }
                    section("Enabled", rows.filter { $0.data.flag("enabled") }, selection: selection)
                    section("Disabled", rows.filter { !$0.data.flag("enabled") }, selection: selection)
                    if rows.isEmpty && !selection.search.isEmpty {
                        Text("No skills match “\(selection.search)”").font(KFont.caption()).foregroundStyle(K.text3)
                            .padding(10)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .sheet(isPresented: $creating) { SkillEditorView() }
    }

    @ViewBuilder private func section(_ title: String, _ items: [WorkspaceRow], selection: LibrarySelection) -> some View {
        if !items.isEmpty {
            SectionLabel(title: title)
            ForEach(items, id: \.id) { row in
                ListRow(title: row.data.text("name"), subtitle: subtitle(row), selected: selection.selectedID == row.id,
                        action: { selection.selectedID = row.id }) {
                    IconTile(icon: "file-text")
                } trailing: {
                    KToggle(isOn: Binding(get: { row.data.flag("enabled") }, set: { app.setSkill(row, enabled: $0) }))
                        .disabled(app.workspace.commands.active.contains("skill.toggle:" + row.id.uuidString))
                        .accessibilityLabel("Skill \(row.data.text("name"))")
                }
            }
        }
    }

    private func subtitle(_ row: WorkspaceRow) -> String {
        let scope = row.projectId.flatMap { app.workspace.find("PROJECT", $0)?.data.text("name") } ?? "All projects"
        return "v\(row.version) · " + scope
    }
}
