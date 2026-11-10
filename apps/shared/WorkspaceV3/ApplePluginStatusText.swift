import BlotAppleIntegrations
import BlotDomain
import SwiftUI

struct ApplePluginStatusText: View {
    let plugin: ApplePluginID
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var status = "Подключить"
    private var connected: Bool { status == "Подключено" || status == "Доступ ограничен" }
    var body: some View {
        Text(status)
            .foregroundStyle(connected ? Color.green : .primary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(connected ? Color.green.opacity(0.12) : Color.clear, in: Capsule())
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
        guard let connection = store.snapshot.connections.first(where: { $0.pluginId == plugin.rawValue && $0.deviceId == store.snapshot.localDeviceID && $0.state == .connected }),
              let controller = store.appleIntegrations else { status = "Подключить"; return }
        status = await controller.status(plugin, resources: connection.resourceIds ?? [])
    }
}
