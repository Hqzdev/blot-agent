import BlotAppleIntegrations
import BlotDomain
import SwiftUI

struct ApplePluginStatusText<Label: View>: View {
    let plugin: ApplePluginID
    let label: (Bool) -> Label
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var connected = false

    var body: some View {
        label(connected)
            .task(id: store.snapshot.toolInvocations) { await refresh() }
            .task(id: store.snapshot.connections) { await refresh() }
            .task(id: store.appleIntegrations?.revision) { await refresh() }
            .task(id: phase) { if phase == .active { await refresh() } }
    }
    private func refresh() async {
        guard plugin.available else { connected = false; return }
        if let deviceID = store.snapshot.localDeviceID,
           !AppleInvocationRecovery.pending(plugin: plugin, deviceID: deviceID, actions: store.snapshot.preparedActions ?? [], invocations: store.snapshot.toolInvocations ?? []).isEmpty {
            connected = false; return
        }
        guard let connection = store.snapshot.connections.first(where: { $0.pluginId == plugin.rawValue && $0.deviceId == store.snapshot.localDeviceID && $0.state == .connected }),
              let controller = store.appleIntegrations else { connected = false; return }
        let accessible = await controller.accessible(plugin, resources: connection.resourceIds ?? [])
        guard !_Concurrency.Task.isCancelled else { return }
        connected = accessible
    }
}
