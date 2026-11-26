import BlotDesign
import SwiftUI
import UIKit

struct PhoneGeneralSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        @Bindable var store = store
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "Permissions") {
                Button { store.navigate(.permissions) } label: {
                    PhoneSettingsRow(title: "Agent access", detail: "Tools and action confirmations are configured separately for each specialist.")
                }.buttonStyle(.plain)
                PhoneSettingsDivider()
                PhoneSettingsRow(title: "Credentials", detail: "Sign-in keys and tokens are stored in the system Keychain.", showsChevron: false)
                PhoneSettingsDivider()
                Button { PhoneSystemSettings.open() } label: {
                    PhoneSettingsRow(title: "System permissions", detail: "Camera, photos, microphone and notifications.")
                }.buttonStyle(.plain)
            }
            PhoneSettingsGroup(title: "General") {
                PhoneSettingsValueRow(title: "Language", detail: "App interface language.") {
                    WorkspaceChoice(title: store.t("Language"), selection: $store.languageSelection, options: [.init("system", store.t("System default")), .init("ru", "Русский"), .init("en", "English")], showsTitle: false)
                }
            }
            WorkspaceVoiceSettingsView()
        }
    }
}

enum PhoneSystemSettings {
    @MainActor static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct PhoneAppearanceSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .system
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    @AppStorage(PhoneSettingsPreferenceKey.compactMessages) private var compactMessages = false
    var body: some View {
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "Appearance", detail: "The system theme follows the appearance of iOS.") {
                PhoneSettingsValueRow(title: "Theme") {
                    WorkspaceChoice(title: store.settingsText("Theme"), selection: $theme, options: [.init(.system, store.settingsText("System")), .init(.light, store.settingsText("Light")), .init(.dark, store.settingsText("Dark"))], showsTitle: false)
                }
            }
            PhoneSettingsGroup(title: "Interface") {
                PhoneSettingsToggle(title: "Compact messages", detail: "Less space between messages and smaller bubble padding.", isOn: $compactMessages)
            }
            PhoneSettingsGroup(title: "Motion") {
                PhoneSettingsToggle(title: "Reduce motion", detail: "Reduces panel movement and message animations. System settings also apply.", isOn: $reduceMotion)
            }
        }
    }
}

struct PhoneUpdatesSettingsView: View {
    var body: some View { PhoneSettingsPage { WorkspaceUpdatesView() } }
}
