import BlotDesign
import BlotDomain
import SwiftUI

/// Uses the original full-page settings layout and controls with account-backed values.
struct MacLiveTeamSettings: View {
    let route: WorkspaceRoute
    var searchFocusRequest = 0
    @Environment(WorkspaceStore.self) private var store
    private var initialPane: MacTeamSettingsPane {
        switch route {
        case .account: .account
        case .appearance: .appearance
        case .notifications: .notifications
        case .personalization: .personalization
        case .usage: .usage
        case .memory: .memory
        case .connections: .connections
        case .mcp: .mcp
        case .permissions, .permissionRules: .privacy
        default: .general
        }
    }
    var body: some View {
        MacTeamSettingsLayout(close: { store.settingsRoute = nil }, searchFocusRequest: searchFocusRequest,
            initialPane: initialPane) { pane in
            MacLiveTeamSettingsContent(pane: pane)
        }
    }
}

private struct MacLiveTeamSettingsContent: View {
    @Environment(\.openWindow) private var openWindow
    let pane: MacTeamSettingsPane
    @Environment(WorkspaceStore.self) private var store
    @State private var editingMemoryID: UUID?
    @ViewBuilder var body: some View {
        @Bindable var store = store
        switch pane {
        case .appearance: MacTeamPersonalSettingsContent(pane: .appearance)
        case .personalization: MacSettingsPersonalizationPane()
        case .shortcuts: MacSettingsShortcutsPane()
        case .general: MacSettingsGeneralPane()
        case .profile: MacSettingsProfilePane()
        case .account: MacSettingsAccountPane()
        case .storage: MacSettingsStoragePane()
        case .updates:
            MacTeamSettingsSection(title: "Версия приложения") {
                MacTeamSettingsRow(title: "Blot") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .foregroundStyle(.secondary)
                }
            }
        case .usage: MacSettingsUsagePane()
        case .notifications: MacSettingsNotificationsPane()
        case .memory:
            MacTeamSettingsSection(title: "Память агентов") {
                if store.snapshot.memories.isEmpty {
                    MacTeamSettingsRow(title: "Сохранённых воспоминаний пока нет", detail: "Выберите «Запомнить» в действиях сообщения.") { EmptyView() }
                }
                ForEach(store.snapshot.memories, id: \.metadata.id) { memory in
                    MacTeamSettingsRow(title: memory.content) {
                        Button("Изменить") {
                            editingMemoryID = memory.metadata.id; store.selectedRecordID = memory.metadata.id
                            store.form.memory.content = memory.content
                        }.buttonStyle(WorkspaceButtonStyle(.secondary))
                    }
                    if editingMemoryID == memory.metadata.id {
                        TextEditor(text: $store.form.memory.content).frame(height: 100).padding(.vertical, 12)
                        HStack {
                            Button("Сохранить") { _Concurrency.Task {
                                await store.perform(.saveMemory)
                                if store.error == nil { editingMemoryID = nil }
                            }}.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(store.busy)
                            Button("Удалить", role: .destructive) { store.deleteMemory(memory.metadata.id); editingMemoryID = nil }
                                .buttonStyle(.plain)
                        }.padding(.bottom, 12)
                    }
                }
            }
        case .connections:
            MacTeamSettingsSection(title: "Приложения и шаблоны") {
                MacTeamSettingsLink(title: "Каталог", actionTitle: "Открыть каталог") {
                    openWindow(id: MacMarketplaceWindow.sceneID)
                }
            }
            MacTeamSettingsSection(title: "Подключённые приложения") {
                if store.snapshot.connections.isEmpty {
                    MacTeamSettingsRow(title: "Нет подключённых аккаунтов") { EmptyView() }
                }
                ForEach(store.snapshot.connections, id: \.metadata.id) { connection in
                    MacTeamSettingsRow(title: connection.service, detail: connection.accountName) {
                        MacTeamBadge(text: connection.state.rawValue)
                    }
                }
            }
        case .mcp:
            MacTeamSettingsSection(title: "MCP-серверы") {
                if store.snapshot.mcpConnections.isEmpty {
                    MacTeamSettingsRow(title: "Нет подключённых MCP-серверов") { EmptyView() }
                }
                ForEach(store.snapshot.mcpConnections, id: \.metadata.id) { connection in
                    MacTeamSettingsRow(title: connection.name, detail: connection.endpoint) { MacTeamBadge(text: connection.state.rawValue) }
                }
            }
        case .privacy:
            MacTeamSettingsSection(title: "Данные и приватность") {
                MacTeamSettingsRow(title: "Учётные данные", detail: "Токены входа хранятся в системной Связке ключей.") { EmptyView() }
                Divider()
                MacTeamSettingsRow(title: "Контекст модели", detail: "Для ответа передаются инструкции агента, контекст переписки и результаты разрешённых инструментов.") { EmptyView() }
            }
            MacTeamSettingsSection(title: "Разрешения агентов") {
                ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                    MacTeamSettingsRow(title: agent.name) { Text(store.t(agent.accessMode.rawValue)).foregroundStyle(.secondary) }
                }
            }
        }
        WorkspaceFeedback()
    }
}
