import SwiftUI

/// The selected model is frozen in an agent revision when it is saved.
struct WorkspaceAgentRuntimeOptions: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Picker(store.t("Model"), selection: $store.form.agent.modelID) {
            Text("GigaChat").tag("gigachat")
            Text(store.t("Compatible API")).tag("compatible")
        }
    }
}
