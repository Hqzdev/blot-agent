import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceGroupEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selected: Set<UUID> = []
    @State private var coordinator: UUID?

    var body: some View {
        NavigationStack {
            Form {
                TextField(store.t("Group name"), text: $title)
                Section(store.t("Participants")) {
                    ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                        Toggle(agent.name, isOn: Binding(get: { selected.contains(agent.metadata.id) }, set: { enabled in
                            if enabled { selected.insert(agent.metadata.id); if coordinator == nil { coordinator = agent.metadata.id } }
                            else { selected.remove(agent.metadata.id); if coordinator == agent.metadata.id { coordinator = selected.sorted { $0.uuidString < $1.uuidString }.first } }
                        }))
                    }
                }
                if !selected.isEmpty {
                    Picker(store.t("Coordinator"), selection: $coordinator) {
                        ForEach(store.snapshot.agents.filter { selected.contains($0.metadata.id) }, id: \.metadata.id) { agent in
                            Text(agent.name).tag(Optional(agent.metadata.id))
                        }
                    }
                }
                WorkspaceFeedback()
            }
            .navigationTitle(store.t("New group"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Create")) {
                        guard let coordinator else { return }
                        let ids = [coordinator] + selected.filter { $0 != coordinator }.sorted { $0.uuidString < $1.uuidString }
                        _Concurrency.Task {
                            if await store.createGroup(title: title, agentIDs: ids) { dismiss() }
                        }
                    }.disabled(store.busy || selected.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.frame(minWidth: 320, minHeight: 360)
    }
}
