import BlotDesign
import SwiftUI

struct PersonalSettingsView: View {
    @Environment(AppState.self) private var app
    @Bindable var settings: SettingsState
    var body: some View {
        @Bindable var app = app
        switch settings.section {
        case .appearance:
            SettingsGroup(title: "Theme") {
                SettingsRow(title: "Appearance", detail: "System follows your Mac's appearance, including automatic switching. Light and Dark override it for Blot only.") {
                    KSegmented(options: ThemePreference.allCases,
                               selection: Binding(get: { app.theme }, set: { app.chooseTheme($0) }),
                               label: { $0.title }, title: "Appearance")
                }
            }
            SettingsGroup(title: "Interface") {
                SettingsRow(title: "Text size", detail: "Scales text across Blot. Larger sizes also follow the macOS text size.") {
                    SettingsChoice(title: "Text size", value: $settings.fontSize, options: TextSizePreference.allCases.map(\.rawValue))
                }
                SettingsDivider()
                SettingsToggleRow(title: "Show agent avatars", detail: "Display role portraits alongside team messages.", value: $settings.showAvatars)
                SettingsDivider()
                SettingsToggleRow(title: "Reduce motion", detail: "Prefer quieter transitions and fewer animated effects.", value: $settings.reduceMotion)
            }
        case .notifications:
            SettingsGroup(title: "Tasks") {
                SettingsRow(title: "Task finished", detail: "Choose when to show completion notifications.") {
                    SettingsChoice(title: "Task finished notifications", value: $settings.completionNotice, options: ["When in background", "Always", "Never"])
                }
                SettingsDivider()
                SettingsToggleRow(title: "Approval needed", detail: "Let me know when an agent is waiting for a decision.", value: $settings.approvalNotifications)
                SettingsDivider()
                SettingsToggleRow(title: "Task failed", detail: "Show a notification when a task needs attention.", value: $settings.failureNotifications)
            }
            SettingsGroup(title: "Delivery") {
                SettingsToggleRow(title: "Play a sound", value: $settings.notificationSound)
                SettingsDivider()
                SettingsToggleRow(title: "Show message previews", detail: "Include a short task summary in notifications.", value: $settings.notificationPreview)
            }
        case .shortcuts:
            SettingsGroup(title: "Navigation") {
                shortcut("New task / New run", "⌘ N")
                SettingsDivider()
                shortcut("Search tasks, files and actions", "⌘ K")
                SettingsDivider()
                shortcut("Close a menu, sheet or the command palette", "Esc")
                SettingsDivider()
                shortcut("Settings", "⌘ ,")
                SettingsDivider()
                shortcut("Blot Code · Task", "⌘ 1")
                SettingsDivider()
                shortcut("Motes · Team chat", "⌘ 2")
                SettingsDivider()
                shortcut("Motes · Team graph", "⌘ 3")
                SettingsDivider()
                shortcut("Show Pet", "⌥ Space")
                SettingsDivider()
                shortcut("Show / hide sidebar", "⌃ ⌘ S")
            }
            Text("These shortcuts match the app menu.").font(KFont.caption()).foregroundStyle(K.text3)
        case .account:
            SettingsGroup(title: "Profile") {
                SettingsRow(title: app.profileDetails.name, detail: app.currentUser?.email ?? "") {
                    InitialsAvatar(initials: app.profileDetails.initials, size: 36,
                                   fill: K.profileAvatar, foreground: K.onInverse, bordered: false)
                }
                SettingsDivider()
                SettingsRow(title: "Public profile", detail: "Name, username, bio and showcase are stored on this Mac.") {
                    KButton(title: "Open profile", icon: "user") { app.showingSettings = false; app.openProfile() }
                }
            }
            SettingsGroup(title: "Session") {
                SettingsRow(title: "Signed in on this Mac", detail: "Signing out keeps your data on the server.") {
                    KButton(title: "Sign out", icon: "log-out", kind: .danger, loading: app.isSigningOut) { app.signOut() }
                }
            }
        case .billing:
            SettingsGroup(title: "Usage") {
                SettingsRow(title: "Token usage", detail: "Spent and reserved tokens are recorded per run by the backend.") {
                    KButton(title: "Open Models", icon: "cpu") { settings.section = .models }
                }
                SettingsDivider()
                SettingsRow(title: "Run budgets", detail: "Each run has its own limit. Raise it from the run’s Results tab.")
            }
            SettingsGroup(title: "Billing") {
                SettingsRow(title: "Plan and payments", detail: "Billing is not connected in this build.") {
                    StatusBadge("Not connected")
                }
            }
        default: EmptyView()
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        SettingsRow(title: title) {
            Text(keys).font(KFont.mono(12)).foregroundStyle(K.text2)
                .padding(.horizontal, 8).frame(height: 24).kCard(radius: K.rSm, fill: K.surface2)
        }
    }
}
