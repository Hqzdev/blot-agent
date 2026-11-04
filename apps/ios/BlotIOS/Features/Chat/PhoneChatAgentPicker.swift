import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneChatAgentPicker: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    _Concurrency.Task { await store.chooseChatAgent(nil) }
                } label: { BlotLabel(store.t("Just chat with AI"), symbol: "bubble.left.and.bubble.right") }
                ForEach(store.snapshot.agents.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }, id: \.metadata.id) { agent in
                    Button { _Concurrency.Task { await store.chooseChatAgent(agent.metadata.id) } } label: {
                        PhoneAgentRow(agent: agent)
                    }
                }
                WorkspaceFeedback()
            }
            .buttonStyle(.plain).disabled(store.busy)
            .searchable(text: $query, prompt: store.t("Choose an agent"))
            .navigationTitle(store.t("Choose an agent")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("Close")) { store.agentPickerVisible = false }
                }
            }
        }
    }
}
