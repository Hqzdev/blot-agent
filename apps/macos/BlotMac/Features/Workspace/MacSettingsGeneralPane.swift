import BlotDesign
import ServiceManagement
import SwiftUI

struct MacSettingsGeneralPane: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage(MacTeamPreferenceKey.sendOnReturn) private var sendOnReturn = true
    @AppStorage(MacTeamPreferenceKey.composerHints) private var composerHints = true
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 42) {
            MacTeamSettingsSection(title: "Разрешения") {
                MacTeamSettingsLink(title: "Доступ агентов", detail: "Доступ к инструментам и подтверждение действий настраиваются отдельно для каждого специалиста.", actionTitle: "Настроить") {
                    store.settingsRoute = .permissions
                }
                Divider()
                MacTeamSettingsRow(title: "Учётные данные", detail: "Ключи и токены входа хранятся в системной Связке ключей.") {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                }
            }
            MacTeamSettingsSection(title: "Общие") {
                MacTeamSettingsRow(title: "Язык", detail: "Язык интерфейса приложения.") {
                    MacTeamSelect(title: "Язык", selection: $store.language,
                        options: [.init("Русский", "ru"), .init("English", "en")], showsTitle: false)
                }
                Divider()
                MacTeamSettingsToggle(title: "Открывать при входе в систему", detail: "Запускать Blot вместе с macOS.",
                    isOn: Binding(get: { launchesAtLogin }, set: setLaunchAtLogin))
            }
            MacTeamSettingsSection(title: "Сообщения") {
                MacTeamSettingsToggle(title: "Отправлять по Enter", detail: "Если выключено, Enter переносит строку. ⌘Enter всегда отправляет сообщение.", isOn: $sendOnReturn)
                Divider()
                MacTeamSettingsToggle(title: "Подсказки под полем ввода", detail: "Показывать подсказку о файлах и задачах для агента.", isOn: $composerHints)
            }
        }
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
