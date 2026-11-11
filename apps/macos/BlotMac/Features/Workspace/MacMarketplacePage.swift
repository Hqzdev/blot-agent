import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

/// The catalog uses the main workspace's navigation and authenticated session.
struct MacMarketplacePage: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var detail: Detail?
    @State private var appleStatuses: [String: String] = [:]
    @Environment(\.scenePhase) private var scenePhase

    private enum Detail: Identifiable {
        case plugin(MacTeamPlugin), template(MacDemoTemplate)
        var id: String {
            switch self {
            case .plugin(let plugin): "plugin-" + plugin.id
            case .template(let template): "template-" + template.id
            }
        }
    }

    private var plugins: [MacTeamPlugin] {
        MacTeamSamples.plugins.map { item in
            var plugin = item
            plugin.accounts = store.snapshot.connections.filter {
                ($0.pluginId == item.id || $0.service == item.name) && $0.state == .connected && ($0.pluginId == nil || $0.deviceId == store.snapshot.localDeviceID)
            }.map(\.accountName)
            if ApplePluginID(rawValue: item.id) != nil { plugin.connectionStatus = appleStatuses[item.id] ?? "Подключить" }
            return plugin
        }
    }

    var body: some View {
        Group {
            if store.isRestoringSession {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.mode == .live && store.snapshot.ownerID == nil {
                ContentUnavailableView("Войдите в Blot", systemImage: "person.crop.circle",
                    description: Text("Каталог доступен после входа в аккаунт."))
            } else {
                MacTeamMarketplaceContent(plugins: plugins,
                    selectPlugin: { detail = .plugin($0) }, selectTemplate: { detail = .template($0) },
                    topInset: 0, pluginActionTitle: "Подробнее",
                    subtitle: "Готовые специалисты и приложения для вашей команды.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink)
        .workspacePanelSheet(item: $detail) { item in
            switch item {
            case .plugin(let plugin): MacMarketplacePluginDetail(plugin: plugin).environment(store)
            case .template(let template): MacMarketplaceTemplateDetail(template: template).environment(store)
            }
        }
        .task(id: store.snapshot.toolInvocations) { await refreshAppleStatuses() }
        .task(id: store.snapshot.connections) { await refreshAppleStatuses() }
        .task(id: store.appleIntegrations?.revision) { await refreshAppleStatuses() }
        .task(id: scenePhase) { if scenePhase == .active { await refreshAppleStatuses() } }
        .onChange(of: store.snapshot.ownerID) { _, ownerID in
            if store.mode == .live && ownerID == nil {
                detail = nil
            }
        }
    }
    private func refreshAppleStatuses() async {
        for plugin in ApplePluginID.allCases {
            if let deviceID = store.snapshot.localDeviceID,
               !AppleInvocationRecovery.pending(plugin: plugin, deviceID: deviceID, actions: store.snapshot.preparedActions ?? [], invocations: store.snapshot.toolInvocations ?? []).isEmpty {
                appleStatuses[plugin.rawValue] = "Нужна проверка"; continue
            }
            if let connection = store.snapshot.connections.first(where: { $0.pluginId == plugin.rawValue && $0.deviceId == store.snapshot.localDeviceID }),
               let controller = store.appleIntegrations {
                appleStatuses[plugin.rawValue] = await controller.status(plugin, resources: connection.resourceIds ?? [])
            } else { appleStatuses[plugin.rawValue] = plugin.available ? "Подключить" : "Доступно на Mac" }
        }
    }

}
