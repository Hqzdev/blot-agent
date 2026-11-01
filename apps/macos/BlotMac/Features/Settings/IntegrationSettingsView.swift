import BlotDesign
import SwiftUI

struct IntegrationSettingsView: View {
    @Bindable var settings: SettingsState
    @State private var addServer = false
    var body: some View {
        switch settings.section {
        case .servers:
            SettingsGroup(title: "Configured servers",
                          detail: "Server connections are not active in this build; these entries are saved for this session.",
                          action: { KButton(title: "Add server", icon: "plus") { addServer = true } }) {
                ForEach(settings.servers, id: \.self) { server in
                    SettingsRow(title: server, detail: "Not connected") {
                        HStack(spacing: 12) {
                            KToggle(isOn: Binding(
                                get: { settings.enabledServers.contains(server) },
                                set: { enabled in
                                    if enabled { settings.enabledServers.insert(server) }
                                    else { settings.enabledServers.remove(server) }
                                }
                            )).accessibilityLabel("Enable \(server)")
                            IconButton(icon: "trash-2", help: "Remove \(server)") {
                                settings.servers.removeAll { $0 == server }
                                settings.enabledServers.remove(server)
                            }
                        }
                    }
                    if server != settings.servers.last { SettingsDivider() }
                }
                if settings.servers.isEmpty {
                    EmptyState(icon: "server", title: "No MCP servers", detail: "Add a server to keep its configuration here.")
                }
            }
            .sheet(isPresented: $addServer) {
                SettingsEditSheet(title: "Add MCP server", label: "Server name") { name in
                    if !settings.servers.contains(name) { settings.servers.append(name) }
                }
            }
        case .git:
            SettingsGroup(title: "Git") {
                SettingsRow(title: "Branch prefix", detail: "Prefix for branches created by the agent.") {
                    KTextField(text: $settings.gitBranch, placeholder: "codex/", mono: true).frame(width: 160)
                }
                SettingsDivider()
                SettingsToggleRow(title: "Include untracked files", detail: "Show new files alongside existing changes in review.", value: $settings.includeUntracked)
                SettingsDivider()
                SettingsToggleRow(title: "Confirm before committing", detail: "Ask before creating a commit from task changes.", value: $settings.confirmCommit)
            }
            SettingsGroup(title: "GitHub") {
                SettingsRow(title: "GitHub account", detail: "Connections will be available when integrations are enabled.") {
                    StatusBadge("Not connected")
                }
            }
        case .editors:
            SettingsGroup(title: "Files & folders") {
                SettingsRow(title: "Default editor", detail: "Open project files in your preferred editor.") {
                    SettingsChoice(title: "Open files in", value: $settings.editor, options: ["VS Code", "Xcode", "Cursor", "System default"])
                }
                SettingsDivider()
                SettingsToggleRow(title: "Preview files in Blot", detail: "Show a file preview before opening it externally.", value: $settings.editorPreview)
            }
        case .browser:
            SettingsGroup(title: "Browser") {
                SettingsRow(title: "Open links in", detail: "Choose where task links open.") {
                    SettingsChoice(title: "Browser", value: $settings.browser, options: ["System default", "Safari", "Chrome", "Blot browser"])
                }
                SettingsDivider()
                SettingsToggleRow(title: "Show browser previews", detail: "Display web previews alongside task results.", value: $settings.browserPreview)
                SettingsDivider()
                SettingsToggleRow(title: "Ask before browser actions", detail: "Request approval before submitting forms or changing external content.", value: $settings.askBrowserActions)
            }
        default: EmptyView()
        }
    }
}
