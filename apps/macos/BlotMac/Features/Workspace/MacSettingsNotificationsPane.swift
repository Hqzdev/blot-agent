import BlotDesign
import BlotDomain
import SwiftUI
import UserNotifications

struct MacSettingsNotificationsPane: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus?
    private var chats: [BlotV3.Conversation] { store.snapshot.conversations.filter { !$0.archived } }
    var body: some View {
        VStack(alignment: .leading, spacing: 42) {
            MacTeamSettingsSection(title: "Blot") {
                MacTeamSettingsRow(title: "Системные уведомления", detail: "Разрешение macOS на уведомления приложения.") {
                    if let status {
                        Text(status == .authorized || status == .provisional ? "Разрешены" : "Не разрешены").foregroundStyle(.secondary)
                    } else { ProgressView().controlSize(.small) }
                }
                Divider()
                if status == .notDetermined {
                    MacTeamSettingsLink(title: "Разрешение macOS", actionTitle: "Разрешить") { requestPermission() }
                } else {
                    MacTeamSettingsLink(title: "Управление уведомлениями", detail: "Звуки, баннеры и показ на экране блокировки.", actionTitle: "Открыть настройки") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(url) }
                    }
                }
            }
            MacTeamSettingsSection(title: "Чаты команды", detail: "Выберите, какие переписки должны уведомлять о новых сообщениях.") {
                if chats.isEmpty { MacTeamSettingsRow(title: "Переписок пока нет") { EmptyView() } }
                ForEach(chats, id: \.metadata.id) { chat in
                    MacTeamSettingsRow(title: chat.title) {
                        MacTeamSelect(title: "Уведомления: " + chat.title, selection: Binding(
                            get: { store.chatInteractions.isMuted(chat.metadata.id) },
                            set: { muted in if muted != store.chatInteractions.isMuted(chat.metadata.id) { store.toggleChatMute(chat.metadata.id) } }),
                            options: [.init("Включены", false), .init("Без звука", true)], showsTitle: false)
                    }
                    if chat.metadata.id != chats.last?.metadata.id { Divider() }
                }
            }
        }.task { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }
    private func requestPermission() {
        _Concurrency.Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            } catch { store.error = "Не удалось запросить разрешение на уведомления." }
        }
    }
}
