import BlotDomain
import BlotDesign
import SwiftUI
import UserNotifications

struct PhoneNotificationSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var requesting = false
    @State private var status: UNAuthorizationStatus = .notDetermined
    private var allowed: Bool { [.authorized, .provisional, .ephemeral].contains(status) }
    var body: some View {
        @Bindable var store = store
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "System notifications", detail: "iOS permission for application notifications.") {
                PhoneSettingsRow(title: "Notifications", value: store.settingsText(allowed ? "Allowed" : "Not allowed"), showsChevron: false)
                PhoneSettingsDivider()
                Button {
                    if status == .notDetermined {
                        requesting = true
                        _Concurrency.Task {
                            store.notificationPreferences.enabled = await store.notifications.requestAccess()
                            status = await store.notifications.authorizationStatus()
                            requesting = false
                        }
                    } else { PhoneSystemSettings.open() }
                } label: {
                    PhoneSettingsRow(title: "Notification settings", detail: "Sounds, banners and Lock Screen display.")
                }.buttonStyle(.plain).disabled(requesting)
            }
            PhoneSettingsGroup(title: "Notifications") {
                PhoneSettingsToggle(title: "Allow notifications", isOn: enabled).disabled(requesting)
            }
            PhoneSettingsGroup(title: "Notify me about") {
                PhoneSettingsToggle(title: "Agent replies", detail: "When an agent finishes replying", isOn: $store.notificationPreferences.agentReplies)
                PhoneSettingsDivider()
                PhoneSettingsToggle(title: "Completed tasks", detail: "When an agent finishes a task", isOn: $store.notificationPreferences.taskCompletion)
                PhoneSettingsDivider()
                PhoneSettingsToggle(title: "Approval requests", detail: "When an action needs your confirmation", isOn: $store.notificationPreferences.approvalRequests)
                PhoneSettingsDivider()
                PhoneSettingsToggle(title: "Scheduled tasks", detail: "Reminders and scheduled task updates", isOn: $store.notificationPreferences.schedules)
                PhoneSettingsDivider()
                PhoneSettingsToggle(title: "Connection changes", detail: "When a computer or service needs attention", isOn: $store.notificationPreferences.connections)
            }.disabled(!store.notificationPreferences.enabled)
            PhoneSettingsGroup(title: "Team chats", detail: "Choose which conversations notify you about new messages.") {
                if store.snapshot.conversations.isEmpty {
                    PhoneSettingsRow(title: "No conversations yet", showsChevron: false)
                }
                ForEach(Array(store.snapshot.conversations.enumerated()), id: \.element.metadata.id) { index, chat in
                    if index > 0 { PhoneSettingsDivider() }
                    PhoneSettingsValueRow(title: chat.title) {
                        Picker(chat.title, selection: Binding(get: { !store.chatInteractions.isMuted(chat.metadata.id) }, set: { enabled in
                            if enabled == store.chatInteractions.isMuted(chat.metadata.id) { store.toggleChatMute(chat.metadata.id) }
                        })) {
                            Text(store.settingsText("Enabled")).tag(true)
                            Text(store.settingsText("Silent")).tag(false)
                        }.labelsHidden()
                    }
                }
            }
            WorkspaceFeedback()
        }
        .task { status = await store.notifications.authorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { _Concurrency.Task { status = await store.notifications.authorizationStatus() } }
        }
    }
    private var enabled: Binding<Bool> {
        Binding(get: { store.notificationPreferences.enabled }, set: { value in
            if !value { store.notificationPreferences.enabled = false; return }
            requesting = true
            _Concurrency.Task {
                store.notificationPreferences.enabled = await store.notifications.requestAccess()
                status = await store.notifications.authorizationStatus()
                requesting = false
            }
        })
    }
}
