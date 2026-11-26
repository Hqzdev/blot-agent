import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

extension EnvironmentValues {
    @Entry var workspaceConnectionAgentID: UUID? = nil
}

/// Setup stays outside the model. Only a verified connection result resumes its tool call.
struct WorkspacePluginRequestView: View {
    let request: WorkspaceCardContent.ConnectionRequest
    let card: BlotV3.ConversationCard
    let active: Bool
    @Environment(WorkspaceStore.self) private var store
    @State private var setup = false
    @State private var checking = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var local: Bool { store.snapshot.localDeviceID == card.executorDeviceId }
    private var plugin: PluginCatalogEntry? { PluginCatalog.all.first { $0.id == request.pluginID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let plugin {
                    if let apple = plugin.appleID { ApplePluginIcon(plugin: apple, size: 36) }
                    else { Image(plugin.asset).resizable().scaledToFit().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 10)) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.name).font(.headline)
                    if let agent = store.snapshot.agents.first(where: { $0.metadata.id == request.agentID }) {
                        Text((ru ? "Для агента " : "For agent ") + agent.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text(request.reason).fixedSize(horizontal: false, vertical: true)
            if active {
                Text(local ? (ru ? "Выберите аккаунт и ресурсы в окне подключения. После выдачи доступа агент продолжит задачу." : "Choose the account and resources in setup. Your agent continues after access is granted.")
                    : (ru ? "Откройте эту карточку на устройстве, которое выполняет задачу." : "Open this card on the device executing the task."))
                    .font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { connect; verify; skip }
                    VStack(alignment: .leading, spacing: 10) { connect; verify; skip }
                }
            } else {
                Text(card.responseJSON.flatMap { try? JSONDecoder().decode(WorkspaceCardResponse.self, from: Data($0.utf8)) }?.action == "connected"
                     ? (ru ? "Подключение подтверждено" : "Connection confirmed") : (ru ? "Запрос закрыт" : "Request closed"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .workspacePanelSheet(isPresented: $setup, onDismiss: { _Concurrency.Task { await finishIfConnected() } }) {
            WorkspacePluginSetupView(pluginID: request.pluginID).environment(store)
                .environment(\.workspaceConnectionAgentID, request.agentID)
        }
    }
    private var connect: some View {
        Button(ru ? "Подключить" : "Connect") { setup = true }
            .buttonStyle(WorkspaceButtonStyle(.primary)).disabled(!local || checking || plugin == nil)
    }
    private var verify: some View {
        Button(ru ? "Проверить доступ" : "Check access") { _Concurrency.Task { await finishIfConnected() } }
            .buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(!local || checking)
    }
    private var skip: some View {
        Button(ru ? "Не сейчас" : "Not now") { _Concurrency.Task { await respond("dismiss") } }
            .buttonStyle(WorkspaceButtonStyle(.quiet)).disabled(checking)
    }
    private func finishIfConnected() async {
        guard active, local, !checking else { return }
        checking = true; failure = nil
        defer { checking = false }
        do {
            try await store.refreshMCP()
            guard let commands = store.pluginCommands,
                  try await commands.pluginDirectory().isConnected(pluginID: request.pluginID, agentID: request.agentID) else {
                failure = ru ? "Подключение ещё не завершено или агенту не выдан доступ." : "Setup is incomplete or this agent has not been granted access."
                return
            }
            await respond("connected")
        } catch { failure = WorkspaceFailureCopy.message(error) }
    }
    private func respond(_ action: String) async {
        guard let commands = store.cardCommands else { return }
        do {
            try await commands.respondToCard(card.metadata.id, version: card.metadata.version, response: .init(action: action))
            try await store.refreshMCP()
        } catch { failure = WorkspaceFailureCopy.message(error) }
    }
}

private struct WorkspacePluginSetupView: View {
    let pluginID: String
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspaceConnectionAgentID) private var agentID
    @WorkspacePresentationDismiss private var dismiss
    private var connectionVersions: [String] {
        (store.snapshot.connections.map { $0.metadata.id.uuidString + ":" + String($0.metadata.version) }
            + store.snapshot.mcpConnections.map { $0.metadata.id.uuidString + ":" + String($0.metadata.version) }).sorted()
    }
    var body: some View {
        NavigationStack {
            Group {
                if let apple = ApplePluginID(rawValue: pluginID) { ApplePluginConnectionView(plugin: apple) }
                else if let google = WorkspaceGooglePlugin(rawValue: pluginID) { WorkspaceGoogleConnectView(plugin: google) }
                else if let messaging = WorkspaceMessagingProvider(rawValue: pluginID) { WorkspaceMessagingConnectView(provider: messaging) }
                else if let preset = WorkspacePluginPreset.find(pluginID) { WorkspacePluginConnectView(preset: preset) }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: PluginCatalog.all.first { $0.id == pluginID }?.name ?? "") {
                    Button(store.t("Close")) { dismiss() }
                }
            }.workspaceEditorChrome()
        }.workspacePanelControls()
        .task(id: connectionVersions) {
            guard let agentID, let commands = store.pluginCommands,
                  (try? await commands.pluginDirectory().isConnected(pluginID: pluginID, agentID: agentID)) == true else { return }
            dismiss()
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 580, minHeight: 500, idealHeight: 650)
        #endif
    }
}
