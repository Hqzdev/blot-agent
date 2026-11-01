import BlotDesign
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsState
    @State private var changeFolder = false
    @State private var checked = false
    var body: some View {
        SettingsGroup(title: "Workspace") {
            SettingsRow(title: "Projects folder", detail: "New projects and tasks started outside a project are stored here.") {
                HStack(spacing: 10) {
                    Text(settings.projectsFolder).font(KFont.mono(12)).foregroundStyle(K.text2)
                    KButton(title: "Change…", height: 28) { changeFolder = true }
                }
            }
            SettingsDivider()
            SettingsRow(title: "Open files in", detail: "Where files and folders open when you click a path.") {
                SettingsChoice(title: "Open files in", value: $settings.editor, options: ["VS Code", "Xcode", "Cursor", "System default"])
            }
            SettingsDivider()
            SettingsRow(title: "Language", detail: "Language of the app interface. Blot answers in the language you write in.") {
                SettingsChoice(title: "Language", value: $settings.language, options: ["Auto detect", "English", "Русский"])
            }
        }
        SettingsGroup(title: "Behavior") {
            SettingsToggleRow(title: "Show in menu bar", detail: "Keep Blot in the menu bar while tasks run with the window closed.", value: $settings.menuBar)
            SettingsDivider()
            SettingsToggleRow(title: "Prevent sleep while a task runs", detail: "Keep the Mac awake until Blot finishes or stops to ask you.", value: $settings.preventSleep)
            SettingsDivider()
            SettingsRow(title: "Notify when a task finishes", detail: "Send a macOS notification when a task completes or needs approval.") {
                SettingsChoice(title: "Task finished notifications", value: $settings.completionNotice, options: ["When in background", "Always", "Never"])
            }
            SettingsDivider()
            SettingsToggleRow(title: "Confirm before quitting", detail: "Warn if quitting would stop tasks that are still running.", value: $settings.confirmQuit)
        }
        SettingsGroup(title: "Updates") {
            SettingsRow(title: "Release channel", detail: "Beta gets new agent features about two weeks earlier.") {
                SettingsChoice(title: "Release channel", value: $settings.releaseChannel, options: ["Stable", "Beta"])
            }
            SettingsDivider()
            SettingsRow(title: "Blot \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")",
                        detail: checked ? "No update service is connected in this build." : "Updates are installed with the app.") {
                KButton(title: "Check now", height: 28) { checked = true }
            }
        }
        .sheet(isPresented: $changeFolder) {
            SettingsEditSheet(title: "Projects folder", label: "Folder path", initialValue: settings.projectsFolder) {
                settings.projectsFolder = $0
            }
        }
    }
}

struct SettingsEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let label: String
    @State private var value: String
    let save: (String) -> Void
    init(title: String, label: String, initialValue: String = "", save: @escaping (String) -> Void) {
        self.title = title
        self.label = label
        _value = State(initialValue: initialValue)
        self.save = save
    }
    private var trimmed: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        KSheet(title, subtitle: "Saved for this session on this Mac.", width: 440) {
            KTextField(label, text: $value, large: true, required: true, autofocus: true) {
                guard !trimmed.isEmpty else { return }
                save(trimmed); dismiss()
            }
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            KButton(title: "Save", kind: .primary) { save(trimmed); dismiss() }
                .disabled(trimmed.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
    }
}
