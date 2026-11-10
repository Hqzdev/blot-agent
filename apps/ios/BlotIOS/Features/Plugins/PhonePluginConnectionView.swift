import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

struct PhonePluginConnectionView: View {
    let plugin: PhonePlugin
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDisconnect = false
    @State private var disconnecting = false

    private var accounts: [BlotV3.Connection] {
        store.snapshot.connections.filter { $0.service == plugin.name && $0.state == .connected }
    }
    private var connected: Bool { !accounts.isEmpty }
    private var busy: Bool { store.busy || disconnecting }

    var body: some View {
        Group {
            if let apple = plugin.appleID { ApplePluginConnectionView(plugin: apple) }
            else { externalBody }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PhonePageHeader(title: store.t(plugin.name), back: { dismiss() }).disabled(busy)
        }
        .environment(\.phonePageTitle, store.t(plugin.name))
    }

    private var externalBody: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(plugin.asset).resizable().scaledToFit().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text(store.t(plugin.description)).foregroundStyle(WorkspaceStyle.secondary)
                ForEach(accounts, id: \.metadata.id) { account in
                    Text(account.accountName).font(.callout).foregroundStyle(WorkspaceStyle.secondary)
                }
                if !connected {
                    Text(store.language == "ru"
                        ? "Подключение этого сервиса пока недоступно в этой версии Blot."
                        : "Connecting this service is not available in this version of Blot yet.")
                        .font(.callout).foregroundStyle(WorkspaceStyle.secondary)
                }
                WorkspaceFeedback()
            }.multilineTextAlignment(.center).frame(maxWidth: 640).padding(PhonePageLayout.inset).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(store.t(connected ? "Connected" : "Connect")) { confirmingDisconnect = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(connected ? .green : WorkspaceStyle.ink)
                .disabled(!connected || busy)
                .accessibilityHint(connected ? store.t("Disconnect") : "")
                .padding(.horizontal, 30).padding(.vertical, 16)
        }
        .background(WorkspaceStyle.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(busy)
        .confirmationDialog(store.t("Disconnect") + " «" + plugin.name + "»?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button(store.t("Disconnect"), role: .destructive) { _Concurrency.Task { await disconnect() } }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(store.language == "ru"
                ? "Агенты потеряют доступ к этому приложению в Blot."
                : "Agents will lose access to this app in Blot.")
        }
    }

    private func disconnect() async {
        disconnecting = true
        defer { disconnecting = false }
        for account in accounts {
            store.selectedRecordID = account.metadata.id
            await store.perform(.removeConnection)
            if store.error != nil { return }
        }
    }
}
