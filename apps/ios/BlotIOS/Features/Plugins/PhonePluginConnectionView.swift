import BlotDesign
import BlotDomain
import SwiftUI

struct PhonePluginConnectionView: View {
    let plugin: PhonePlugin
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let connection = store.snapshot.connections.first(where: { $0.service == plugin.name }) {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plugin.name).font(.headline)
                                Text(connection.accountName).foregroundStyle(WorkspaceStyle.secondary)
                            }
                        } icon: { Image(plugin.asset).resizable().scaledToFit().frame(width: 32, height: 32) }
                        Text(store.t(connection.state == .connected ? "Connected" : "Not connected"))
                    }
                    Section(store.t("Permissions")) {
                        ForEach(connection.scopes, id: \.self) { scope in
                            Text(scope).font(.subheadline)
                        }
                    }
                    Section {
                        Button(store.t("Disconnect"), role: .destructive) {
                            _Concurrency.Task {
                                store.selectedRecordID = connection.metadata.id
                                await store.perform(.removeConnection)
                                if store.error == nil { dismiss() }
                            }
                        }.disabled(store.busy)
                        WorkspaceFeedback()
                    }
                }
            }
            .navigationTitle(store.t("Manage connection")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Close")) { dismiss() } } }
        }
    }
}
