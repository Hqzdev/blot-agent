import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

struct MacMarketplacePluginDetail: View {
    let plugin: MacTeamPlugin
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    @Environment(\.macSheetSize) private var sheetSize
    @State private var confirmingDisconnect = false
    @State private var disconnecting = false
    private var accounts: [BlotV3.Connection] {
        store.snapshot.connections.filter { $0.service == plugin.name && $0.state == .connected }
    }

    var body: some View {
        if let apple = ApplePluginID(rawValue: plugin.id) { ApplePluginConnectionView(plugin: apple) }
        else { externalBody }
    }
    private var externalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        MacTeamPluginIcon(plugin: plugin, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            WorkspaceLocalizedText(plugin.name).font(.title2.weight(.semibold))
                            WorkspaceLocalizedText(plugin.category).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    WorkspaceLocalizedText(plugin.summary).font(.body).foregroundStyle(.secondary)
                    if !accounts.isEmpty {
                        Text("Аккаунты").font(.headline)
                        ForEach(accounts, id: \.metadata.id) { account in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(account.accountName).font(.body.weight(.medium))
                                    Text(account.scopes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                MacTeamBadge(text: "Подключено", color: .green)
                            }.padding(16).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    if accounts.isEmpty {
                        Text("Подключение этого сервиса пока недоступно в этой версии Blot.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let error = store.error { WorkspaceLocalizedText(error).font(.callout).foregroundStyle(.red) }
                }.padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button(accounts.isEmpty ? "Подключить" : "Подключено") { confirmingDisconnect = true }
                    .buttonStyle(WorkspaceButtonStyle()).controlSize(.large)
                    .tint(accounts.isEmpty ? WorkspaceStyle.ink : .green)
                    .disabled(accounts.isEmpty || store.busy || disconnecting)
                Spacer()
            }.padding(18)
        }.frame(width: panelNavigation == nil ? min(560, sheetSize.width) : nil, height: panelNavigation == nil ? min(460, sheetSize.height) : nil).background(WorkspaceStyle.canvas)
            .safeAreaInset(edge: .top, spacing: 0) {
                if panelNavigation != nil { WorkspacePanelFormHeader(title: store.t(plugin.name)) { Button(store.t("Close")) { dismiss() }.disabled(store.busy || disconnecting) } }
            }
            .interactiveDismissDisabled(store.busy || disconnecting)
            .onExitCommand { if !store.busy && !disconnecting { dismiss() } }
            .confirmationDialog("Отключить «\(plugin.name)»?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
                Button("Отключить", role: .destructive) { _Concurrency.Task { await disconnect() } }
                Button("Отмена", role: .cancel) {}
            } message: { Text("Агенты потеряют доступ к этому приложению в Blot.") }
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
