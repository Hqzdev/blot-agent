import BlotDesign
import BlotDomain
import ServiceManagement
import SwiftUI
import UserNotifications

/// Uses the original full-page settings layout and controls with account-backed values.
struct MacLiveTeamSettings: View {
    let route: WorkspaceRoute
    var searchFocusRequest = 0
    @Environment(WorkspaceStore.self) private var store
    private var initialPane: MacTeamSettingsPane {
        switch route {
        case .account: .account
        case .devices, .pair: .devices
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
    let pane: MacTeamSettingsPane
    @Environment(WorkspaceStore.self) private var store
    @AppStorage(MacTeamPreferenceKey.sendOnReturn) private var sendOnReturn = true
    @AppStorage(MacTeamPreferenceKey.composerHints) private var composerHints = true
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var editingMemoryID: UUID?
    @ViewBuilder var body: some View {
        @Bindable var store = store
        switch pane {
        case .appearance, .personalization, .shortcuts:
            MacTeamPersonalSettingsContent(pane: pane)
        case .general:
            MacTeamSettingsSection(title: "Рабочее пространство") {
                MacTeamSettingsRow(title: "Аккаунт", detail: store.form.account.email) { Text(store.accountDisplayName).foregroundStyle(.secondary) }
            }
            MacTeamSettingsSection(title: "Общие") {
                MacTeamSettingsRow(title: "Язык", detail: "Предпочтительный язык пространства и формат дат.") {
                    MacTeamSelect(title: "Язык", selection: $store.language,
                        options: [.init("Русский", "ru"), .init("English", "en")], showsTitle: false)
                }
                Divider()
                MacTeamSettingsToggle(title: "Открывать при входе в систему", isOn: Binding(get: { launchesAtLogin }, set: setLaunchAtLogin))
            }
            MacTeamSettingsSection(title: "Сообщения") {
                MacTeamSettingsToggle(title: "Отправлять по Enter",
                    detail: "Если выключено, Enter переносит строку. ⌘Enter всегда отправляет сообщение.", isOn: $sendOnReturn)
                Divider()
                MacTeamSettingsToggle(title: "Подсказки под полем ввода",
                    detail: "Напоминать о навыках, файлах и расписаниях.", isOn: $composerHints)
            }
        case .profile:
            MacTeamSettingsSection(title: "Личный профиль") {
                MacTeamSettingsRow(title: "Ваше имя", detail: "Отображается в нижней части панели команды.") {
                    TextField("Имя", text: $store.form.account.name).frame(width: 220).accessibilityLabel("Ваше имя")
                }
                Divider()
                MacTeamSettingsRow(title: "Пространство") { Text("Личное пространство").foregroundStyle(.secondary) }
            }
        case .account:
            MacTeamSettingsSection(title: "Пространство") {
                MacTeamSettingsRow(title: "Владелец", detail: store.form.account.email) { Text(store.accountDisplayName).foregroundStyle(.secondary) }
                Divider()
                MacTeamSettingsRow(title: "Команда") { Text("\(store.snapshot.agents.count) агентов").foregroundStyle(.secondary) }
                Divider()
                MacTeamSettingsRow(title: "Подключённые аккаунты") { Text("\(store.snapshot.connections.count)").foregroundStyle(.secondary) }
            }
            MacTeamSettingsSection(title: "Сессия") {
                MacTeamSettingsLink(title: "Текущий аккаунт", actionTitle: "Выйти") { store.signOut() }
            }
        case .devices: WorkspacePairedDevicesView()
        case .storage:
            MacTeamSettingsSection(title: "Файлы и данные") {
                MacTeamSettingsRow(title: "Переписки") { Text("\(store.snapshot.conversations.count)").foregroundStyle(.secondary) }
                Divider()
                MacTeamSettingsRow(title: "Документы") { Text("\(store.snapshot.artifacts.count)").foregroundStyle(.secondary) }
                Divider()
                MacTeamSettingsLink(title: "Файлы пространства", actionTitle: "Открыть") {
                    store.settingsRoute = nil; store.navigate(.files)
                }
            }
        case .updates:
            MacTeamSettingsSection(title: "Версия приложения") {
                MacTeamSettingsRow(title: "Blot") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .foregroundStyle(.secondary)
                }
            }
        case .usage:
            MacTeamSettingsSection(title: "Использование") {
                MacTeamSettingsRow(title: "Вызовы модели") { Text("\((store.snapshot.modelSteps ?? []).count)").foregroundStyle(.secondary) }
                Divider()
                MacTeamSettingsRow(title: "Учтённые токены") {
                    Text("\((store.snapshot.modelSteps ?? []).reduce(0) { $0 + ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0) })").foregroundStyle(.secondary)
                }
            }
        case .notifications:
            MacTeamSettingsSection(title: "События команды") {
                MacTeamSettingsRow(title: "Системные уведомления", detail: "Разрешение macOS на уведомления Blot.") {
                    MacTeamBadge(text: notificationStatus == .authorized ? "Разрешены" : "Не разрешены")
                }
                if notificationStatus == .notDetermined {
                    Divider()
                    MacTeamSettingsLink(title: "Разрешение macOS", actionTitle: "Разрешить") {
                        _Concurrency.Task {
                            do {
                                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                                notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                            } catch { store.error = "Не удалось запросить разрешение на уведомления." }
                        }
                    }
                }
            }.task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
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
    private func setLaunchAtLogin(_ enabled: Bool) {
        _Concurrency.Task {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
                launchesAtLogin = SMAppService.mainApp.status == .enabled
            } catch { store.error = "Не удалось изменить запуск при входе. Проверьте разрешение в настройках macOS." }
        }
    }
}
