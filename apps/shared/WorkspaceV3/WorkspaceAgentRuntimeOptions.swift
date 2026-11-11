import SwiftUI

/// These choices are frozen in an agent revision when it is saved.
struct WorkspaceAgentRuntimeOptions: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        @Bindable var store = store
        DisclosureGroup(store.t("Model and tools")) {
            WorkspaceChoice(title: store.t("Model"), selection: $store.form.agent.modelID,
                options: [.init("gigachat", "GigaChat"), .init("compatible", store.t("Compatible API"))])
            ForEach([("file_read", "Read attached files"), ("document_create", "Create documents"),
                     ("memory_candidate", "Propose memories")], id: \.0) { id, label in
                Toggle(store.t(label), isOn: Binding(get: { store.form.agent.toolIDs.contains(id) }, set: { enabled in
                    store.form.agent.toolIDs.removeAll { $0 == id }
                    if enabled { store.form.agent.toolIDs.append(id) }
                }))
            }
        }
    }
}
