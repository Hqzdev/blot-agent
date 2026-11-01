import BlotDesign
import Observation
import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", notifications = "Notifications"
    case shortcuts = "Keyboard shortcuts", account = "Account", billing = "Usage & billing"
    case permissions = "Permissions", models = "Models", environments = "Environments"
    case instructions = "Instructions", skills = "Skills", servers = "MCP servers"
    case git = "Git & GitHub", editors = "Editors", browser = "Browser"
    var id: String { rawValue }
    var group: String {
        switch self {
        case .general, .appearance, .notifications, .shortcuts, .account, .billing: "Personal"
        case .permissions, .models, .environments, .instructions, .skills: "Agent"
        default: "Integrations"
        }
    }
    var icon: String {
        switch self {
        case .general: "sliders-horizontal"
        case .appearance: "sun"
        case .notifications: "bell"
        case .shortcuts: "keyboard"
        case .account: "user"
        case .billing: "chart-bar"
        case .permissions: "shield"
        case .models: "cpu"
        case .environments: "terminal"
        case .instructions: "file-text"
        case .skills: "puzzle"
        case .servers: "server"
        case .git: "git-branch"
        case .editors: "code"
        case .browser: "globe"
        }
    }
}

/// Preferences for this session. Theme, text size and Reduce motion apply immediately; the rest are kept in memory.
@Observable
final class SettingsState {
    var section: SettingsSection = .general
    var search = ""
    var projectsFolder = "~/Developer/blot"
    var editor = "VS Code"
    var language = "Auto detect"
    var menuBar = true
    var preventSleep = true
    var completionNotice = "When in background"
    var confirmQuit = false
    var releaseChannel = "Stable"
    var fontSize = "Default"
    var reduceMotion = false
    var showAvatars = true
    var approvalNotifications = true
    var failureNotifications = true
    var notificationSound = false
    var notificationPreview = true
    var model = ""
    var reasoning = "High"
    var fastModel = true
    var servers = ["Filesystem", "GitHub"]
    var enabledServers: Set<String> = ["Filesystem"]
    var gitBranch = "codex/"
    var includeUntracked = true
    var confirmCommit = true
    var editorPreview = true
    var browser = "System default"
    var browserPreview = true
    var askBrowserActions = true
}
