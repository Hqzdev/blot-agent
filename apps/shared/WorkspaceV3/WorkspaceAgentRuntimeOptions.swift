import SwiftUI

/// The selected model is frozen in an agent revision when it is saved.
struct WorkspaceAgentRuntimeOptions: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        @Bindable var store = store
        WorkspaceChoice(title: store.t("Model"), selection: $store.form.agent.modelID,
            options: [.init("gigachat", "GigaChat"), .init("compatible", store.t("Compatible API"))])
    }
}
