import BlotAppleIntegrations
import BlotDomain
import SwiftUI

struct ApplePluginStatusText: View {
    let plugin: ApplePluginID
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var status = "Подключить"
    var body: some View {
        Text(status)
            .task(id: store.snapshot.toolInvocations) { await refresh() }
            .task(id: store.snapshot.connections) { await refresh() }
            .task(id: store.appleIntegrations?.revision) { await refresh() }
            .task(id: phase) { if phase == .active { await refresh() } }
    }
    private func refresh() async {
        guard plugin.available else { status = "Доступно на Mac"; return }
        if let deviceID = store.snapshot.localDeviceID,
           !AppleInvocationRecovery.pending(plugin: plugin, deviceID: deviceID, actions: store.snapshot.preparedActions ?? [], invocations: store.snapshot.toolInvocations ?? []).isEmpty {
            status = "Нужна проверка"; return
        }
        guard let connection = store.snapshot.connections.first(where: { $0.pluginId == plugin.rawValue && $0.deviceId == store.snapshot.localDeviceID }),
              let controller = store.appleIntegrations else { status = "Подключить"; return }
        status = await controller.status(plugin, resources: connection.resourceIds ?? [])
    }
}
