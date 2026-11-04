import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceLocalSearchView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var messages: [BlotV3.Message] = []
    @State private var failure: String?

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkspaceField(title: "Search", text: $store.form.search.query)
                ForEach(messages, id: \.metadata.id) { message in
                    Button {
                        store.openConversation(message.conversationId)
                        store.messageNavigationTarget = message.metadata.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.snapshot.conversations.first { $0.metadata.id == message.conversationId }?.title ?? store.t("Chat")).font(.headline)
                            Text(message.content).lineLimit(3).foregroundStyle(WorkspaceStyle.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(WorkspaceRowButtonStyle())
                }
                if let failure { Text(failure).foregroundStyle(WorkspaceStyle.secondary) }
                else if messages.isEmpty && !store.form.search.query.isEmpty { Text(store.t("No results")) }
            }.padding(24)
        }
        .task(id: store.form.search.query) {
            do {
                try await _Concurrency.Task.sleep(for: .milliseconds(150))
                messages = try await store.searchLocalMessages(store.form.search.query)
                failure = nil
            } catch is CancellationError { return }
            catch { failure = store.t("Search is unavailable") }
        }
    }
}
