import BlotDesign
import SwiftUI

struct MacTeamIntegrationSettingsContent: View {
    let pane: MacTeamSettingsPane
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var status: String?
    private var connected: [MacTeamPlugin] { presentation.plugins.filter { !$0.accounts.isEmpty } }
    private var servers: [MacDemoConnection] {
        presentation.demo.state.connections.filter { ["composio", "zapier"].contains($0.pluginID) }
    }

    @ViewBuilder var body: some View {
        switch pane {
        case .connections: connections
        case .mcp: mcp
        case .updates: updates
        default: EmptyView()
        }
        if let status { Text(status).font(.system(size: 12)).foregroundStyle(.secondary) }
    }

    @ViewBuilder private var connections: some View {
        MacTeamSettingsSection(title: "Подключённые приложения") {
            ForEach(connected) { plugin in
                HStack(spacing: 12) {
                    MacTeamPluginIcon(plugin: plugin, size: 32)
                    MacTeamSettingsRow(title: plugin.name, detail: "Аккаунтов: \(plugin.accounts.count)") {
                        Button("Настроить") { presentation.sheet = .plugin(plugin) }.buttonStyle(WorkspaceButtonStyle(.secondary))
                    }
                }
                if plugin.id != connected.last?.id { Divider() }
            }
            if connected.isEmpty {
                MacTeamSettingsRow(title: "Пока нет подключений", detail: "Добавьте приложение из каталога.") { EmptyView() }
            }
        }
        MacTeamSettingsSection(title: "Больше возможностей") {
            MacTeamSettingsLink(title: "Каталог приложений", detail: "Почта, календарь, документы и другие инструменты команды.", actionTitle: "Открыть") {
                presentation.open(.library(.marketplace))
                presentation.closeSettings()
            }
        }
    }

    @ViewBuilder private var mcp: some View {
        MacTeamSettingsSection(title: "Подключённые серверы") {
            ForEach(servers) { server in
                MacTeamSettingsRow(title: server.label, detail: server.endpoint.isEmpty ? server.authentication : server.endpoint) {
                    Button("Настроить") {
                        if let plugin = presentation.plugins.first(where: { $0.id == server.pluginID }) {
                            presentation.sheet = .plugin(plugin)
                        }
                    }.buttonStyle(WorkspaceButtonStyle(.secondary))
                }
                if server.id != servers.last?.id { Divider() }
            }
            if servers.isEmpty {
                MacTeamSettingsRow(title: "Нет серверов", detail: "Подключите Composio или Zapier, чтобы настроить инструменты.") { EmptyView() }
            }
        }
        MacTeamSettingsSection(title: "Новый сервер") {
            ForEach(presentation.plugins.filter { $0.category == "MCP" }) { plugin in
                MacTeamSettingsLink(title: plugin.name, detail: plugin.summary, actionTitle: "Добавить") {
                    presentation.sheet = .plugin(plugin)
                }
                if plugin.id != presentation.plugins.last(where: { $0.category == "MCP" })?.id { Divider() }
            }
        }
        Text("В демо адрес сервера и способ авторизации сохраняются локально, без подключения к сети.")
            .font(.system(size: 12)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var updates: some View {
        @Bindable var presentation = presentation
        MacTeamSettingsSection(title: "Приложение") {
            MacTeamSettingsRow(title: "Версия Blot", detail: "Текущая локальная сборка приложения.") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            Divider()
            MacTeamSettingsRow(title: "Канал обновлений") {
                MacTeamSelect(title: "Канал обновлений", selection: $presentation.settings.updateTrack,
                              values: ["Стабильный", "Предварительный"], showsTitle: false)
            }
            Divider()
            MacTeamSettingsToggle(title: "Обновлять автоматически", detail: "Предпочтение обновлений для будущих версий.",
                                  isOn: $presentation.settings.automaticUpdates)
            Divider()
            MacTeamSettingsLink(title: "Проверка обновлений",
                               detail: presentation.settings.lastUpdateCheck.map { "Последняя проверка: " + presentation.dateLabel($0) }
                                   ?? "Проверка ещё не запускалась.", actionTitle: "Проверить") {
                presentation.settings.lastUpdateCheck = Date()
                status = "Демо-проверка завершена. Используется локальная сборка, сетевой запрос не выполнялся."
            }
        }
    }
}
