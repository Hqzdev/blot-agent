import BlotAPI
import BlotDesign
import SwiftUI

/// «12 · Automations» sidebar: search, new schedule, and every schedule with an on/off toggle.
struct AutomationsSidebar: View {
    @Environment(AppState.self) private var app
    @State private var creating = false
    private var rows: [WorkspaceRow] {
        app.workspace.rows("AUTOMATION").filter {
            app.automations.search.isEmpty
                || $0.data.text("name").localizedCaseInsensitiveContains(app.automations.search)
        }
    }

    var body: some View {
        @Bindable var selection = app.automations
        VStack(spacing: 0) {
            KSearchField(placeholder: "Search schedules", text: $selection.search)
                .padding(.horizontal, 12).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    SidebarItem(icon: "plus", label: "New schedule") { creating = true }
                    if !rows.isEmpty { SectionLabel(title: "Schedules") }
                    ForEach(rows, id: \.id) { row in
                        let project = app.workspace.find("PROJECT", row.projectId)?.data.text("name")
                        ListRow(title: row.data.text("name"),
                                subtitle: AutomationSchedule.describe(row) + (project.map { " · " + $0 } ?? ""),
                                selected: selection.selectedID == row.id,
                                action: { selection.selectedID = row.id }) {
                            IconTile(icon: "clock")
                        } trailing: {
                            KToggle(isOn: Binding(get: { row.data.flag("enabled") },
                                                  set: { app.setAutomation(row, enabled: $0) }))
                                .disabled(app.workspace.commands.active.contains("automation.toggle:" + row.id.uuidString))
                                .accessibilityLabel("Schedule \(row.data.text("name"))")
                        }
                    }
                    if rows.isEmpty && !selection.search.isEmpty {
                        Text("No schedules match “\(selection.search)”").font(KFont.caption()).foregroundStyle(K.text3)
                            .padding(10)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .sheet(isPresented: $creating) { AutomationEditorView() }
    }
}
