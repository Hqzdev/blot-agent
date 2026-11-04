import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

struct MacMarketplacePluginDetail: View {
    let plugin: MacTeamPlugin
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macSheetSize) private var sheetSize
    private var accounts: [BlotV3.Connection] {
        store.snapshot.connections.filter { $0.service == plugin.name }
    }

    var body: some View {
        if let apple = ApplePluginID(rawValue: plugin.id) { ApplePluginConnectionView(plugin: apple) }
        else { externalBody }
    }
    private var externalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacTeamSheetHeader(title: "Приложение")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        MacTeamPluginIcon(plugin: plugin, size: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plugin.name).font(.title2.weight(.semibold))
                            Text(plugin.category).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Text(plugin.summary).font(.body).foregroundStyle(.secondary)
                    if !accounts.isEmpty {
                        Text("Аккаунты").font(.headline)
                        ForEach(accounts, id: \.metadata.id) { account in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(account.accountName).font(.body.weight(.medium))
                                    Text(account.scopes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Label(account.state == .connected ? "Подключено" : "Не подключено",
                                    systemImage: account.state == .connected ? "checkmark.circle" : "minus.circle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(16).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Label("Подключение новых аккаунтов пока недоступно в этой версии Blot.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Готово") { dismiss() }.buttonStyle(WorkspaceButtonStyle()).keyboardShortcut(.defaultAction)
            }.padding(18)
        }.frame(width: min(560, sheetSize.width), height: min(460, sheetSize.height)).background(WorkspaceStyle.canvas)
    }
}
