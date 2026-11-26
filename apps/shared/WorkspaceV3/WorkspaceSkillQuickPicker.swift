import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceSkillQuickButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { BlotLabel(store.t("Skills"), symbol: "shippingbox") }
            .workspacePanelSheet(isPresented: $showing) { WorkspaceSkillQuickPicker().environment(store) }
    }
}

struct WorkspaceSkillQuickPicker: View {
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var query = ""
    @State private var running: Selection?
    private struct Selection: Identifiable { let skill: BlotV3.Skill; var id: UUID { skill.metadata.id } }
    private var ru: Bool { store.language == "ru" }
    private var skills: [BlotV3.Skill] {
        (store.snapshot.skills ?? []).filter { !$0.archived && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                TextField(ru ? "Найти навык" : "Find a skill", text: $query)
                if skills.isEmpty { Text(ru ? "Создайте навык в разделе «Навыки» и назначьте его агенту." : "Create a skill in Skills and assign it to an agent.").foregroundStyle(.secondary) }
                ForEach(skills, id: \.metadata.id) { skill in
                    Button { running = .init(skill: skill) } label: {
                        HStack { BlotLabel(skill.name, symbol: "shippingbox"); Spacer(); BlotIcon(symbol: "chevron.right") }
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: store.t("Skills")) {
                    Button(store.t("Close")) { dismiss() }
                }
            }.workspaceEditorChrome()
        }
        .workspacePanelSheet(item: $running) { selection in WorkspaceSkillRunner(skill: selection.skill).environment(store) }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 400)
        #endif
    }
}
