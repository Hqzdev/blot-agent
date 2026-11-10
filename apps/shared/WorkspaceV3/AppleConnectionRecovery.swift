import BlotAppleIntegrations
import BlotDomain
import SwiftUI

/// Interrupted operations are reconciled separately from the connection's single action.
struct AppleConnectionRecovery: ViewModifier {
    let plugin: ApplePluginID
    @Environment(WorkspaceStore.self) private var store
    @State private var presented = false

    private var pending: AppleUncertainAction? {
        guard let deviceID = store.snapshot.localDeviceID else { return nil }
        return AppleInvocationRecovery.pending(plugin: plugin, deviceID: deviceID,
            actions: store.snapshot.preparedActions ?? [], invocations: store.snapshot.toolInvocations ?? []).first
    }

    func body(content: Content) -> some View {
        content
            .task { presented = pending != nil }
            .onChange(of: pending?.id) { _, id in presented = id != nil }
            .alert("Проверьте результат действия", isPresented: $presented, presenting: pending) { action in
                Button("Выполнено") { _Concurrency.Task { await store.resolveAppleInvocation(action.id, succeeded: true) } }
                Button("Не выполнено") { _Concurrency.Task { await store.resolveAppleInvocation(action.id, succeeded: false) } }
                Button("Позже", role: .cancel) {}
            } message: { action in
                Text(action.preparation.consequences + "\n\nПроверьте результат в системном приложении. До вашего решения новые изменения через это подключение приостановлены.")
            }
    }
}
