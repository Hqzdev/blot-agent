import Foundation

enum WorkspaceRoute: String, CaseIterable, Identifiable, Hashable {
    case welcome, signIn, createAccount, verifyEmail, firstRun, firstAgent, createAgent
    case home, chats, archivedChats, search, newChat, chat, running, approval, result, file, review
    case skills, agents, agentProfile, editAgent, files, schedules, createSchedule
    #if os(iOS)
    case overview
    #endif
    case usage, personalization, settingsProfile, settingsStorage, settingsUpdates
    #if os(macOS)
    case marketplace
    #endif
    case settings, appSettings, account, models, permissions, connections, devices, pair, memory, mcp
    case browserSettings, browser, permissionRules, blocked, offline, appearance, notifications, language, recovery
    var id: String { rawValue }
    var isAuthentication: Bool { [.welcome, .signIn, .createAccount, .verifyEmail, .firstRun, .firstAgent, .recovery].contains(self) }
    var isSetting: Bool { [.settings, .settingsProfile, .settingsStorage, .settingsUpdates, .appSettings, .account, .usage, .personalization, .models, .permissions, .connections, .devices, .memory, .mcp, .browserSettings, .permissionRules, .appearance, .notifications, .language].contains(self) }
    var title: String {
        switch self {
        case .welcome: "Blot"
        case .signIn: "Sign in"
        case .createAccount: "New account"
        case .verifyEmail: "Verification"
        case .firstRun: "Workspace setup"
        case .firstAgent: "Your first agent"
        case .createAgent: "New agent"
        case .home, .newChat: "New chat"
        case .chats: "Chats"
        case .archivedChats: "Archive"
        case .search: "Search"
        case .chat, .running, .approval, .result, .offline: "Blot CEO"
        case .file: "week-meal-prep.md"
        case .review: "Code changes"
        case .skills: "Skills"
        case .agents: "Agents"
        case .agentProfile: "Agent"
        case .editAgent: "Edit agent"
        case .files: "Files"
        case .schedules: "Schedules"
        case .createSchedule: "New schedule"
        #if os(iOS)
        case .overview: "Overview"
        #endif
        case .settings: "General"
        case .appSettings: "App settings"
        case .account: "Account"
        case .usage: "Usage"
        case .personalization: "Personalization"
        case .settingsProfile: "Profile"
        case .settingsStorage: "Files and data"
        case .settingsUpdates: "Updates"
        #if os(macOS)
        case .marketplace: "Apps and templates"
        #endif
        case .models: "AI models"
        case .permissions: "Permissions"
        case .connections: "Connections"
        case .devices: "Computers"
        case .pair: "Connect computer"
        case .memory: "Memory"
        case .mcp: "MCP servers"
        case .browserSettings: "Browser"
        case .browser: "Browsing"
        case .permissionRules: "Permission rules"
        case .blocked: "Task blocked"
        case .appearance: "Appearance"
        case .notifications: "Notifications"
        case .language: "Language"
        case .recovery: "Reset password"
        }
    }
}

/// One record per saved reference. Shared routes intentionally have separate platform compositions.
struct WorkspaceReference: Identifiable {
    enum Platform: String { case desktop, ios }
    let platform: Platform
    let number: Int
    let file: String
    let route: WorkspaceRoute
    var id: String { "\(platform.rawValue)-\(number)" }
    var path: String { "screens/\(platform.rawValue)/\(file).png" }
    static let all: [Self] = desktop + phone
    private static let desktop: [Self] = [
        .init(platform: .desktop, number: 1, file: "01-sign-in", route: .signIn),
        .init(platform: .desktop, number: 2, file: "02-create-account", route: .createAccount),
        .init(platform: .desktop, number: 3, file: "03-verify-email", route: .verifyEmail),
        .init(platform: .desktop, number: 4, file: "04-first-run", route: .firstRun),
        .init(platform: .desktop, number: 5, file: "05-new-task", route: .home),
        .init(platform: .desktop, number: 6, file: "06-chat-plan", route: .chat),
        .init(platform: .desktop, number: 7, file: "07-task-running", route: .running),
        .init(platform: .desktop, number: 8, file: "08-approval", route: .approval),
        .init(platform: .desktop, number: 9, file: "09-result-and-file", route: .result),
        .init(platform: .desktop, number: 10, file: "10-code-changes-review", route: .review),
        .init(platform: .desktop, number: 11, file: "11-my-team", route: .agents),
        .init(platform: .desktop, number: 12, file: "12-agent-profile", route: .agentProfile),
        .init(platform: .desktop, number: 13, file: "13-create-agent", route: .createAgent),
        .init(platform: .desktop, number: 14, file: "14-files", route: .files),
        .init(platform: .desktop, number: 15, file: "15-schedules", route: .schedules),
        .init(platform: .desktop, number: 16, file: "16-create-schedule", route: .createSchedule),
        .init(platform: .desktop, number: 17, file: "17-settings-window", route: .settings),
        .init(platform: .desktop, number: 18, file: "18-settings-account", route: .account),
        .init(platform: .desktop, number: 19, file: "19-settings-ai-models", route: .models),
        .init(platform: .desktop, number: 20, file: "20-settings-permissions", route: .permissions),
        .init(platform: .desktop, number: 21, file: "21-settings-connections", route: .connections),
        .init(platform: .desktop, number: 22, file: "22-settings-devices", route: .devices),
        .init(platform: .desktop, number: 23, file: "23-settings-memory", route: .memory),
        .init(platform: .desktop, number: 24, file: "24-settings-mcp-servers", route: .mcp),
        .init(platform: .desktop, number: 25, file: "25-settings-browser", route: .browserSettings),
        .init(platform: .desktop, number: 26, file: "26-task-browser", route: .browser),
        .init(platform: .desktop, number: 27, file: "27-settings-permission-rules", route: .permissionRules),
        .init(platform: .desktop, number: 28, file: "28-task-blocked", route: .blocked)
    ]
    private static let phone: [Self] = [
        .init(platform: .ios, number: 1, file: "01-welcome", route: .welcome),
        .init(platform: .ios, number: 2, file: "02-sign-in", route: .signIn),
        .init(platform: .ios, number: 3, file: "03-create-account", route: .createAccount),
        .init(platform: .ios, number: 4, file: "04-verify-email", route: .verifyEmail),
        .init(platform: .ios, number: 5, file: "05-first-agent", route: .firstAgent),
        .init(platform: .ios, number: 6, file: "06-create-agent", route: .createAgent),
        .init(platform: .ios, number: 7, file: "07-all-chats", route: .chats),
        .init(platform: .ios, number: 8, file: "08-search", route: .search),
        .init(platform: .ios, number: 9, file: "09-new-chat", route: .newChat),
        .init(platform: .ios, number: 10, file: "10-chat-with-ceo", route: .chat),
        .init(platform: .ios, number: 11, file: "11-task-running", route: .running),
        .init(platform: .ios, number: 12, file: "12-approval", route: .approval),
        .init(platform: .ios, number: 13, file: "13-result", route: .result),
        .init(platform: .ios, number: 14, file: "14-file-preview", route: .file),
        .init(platform: .ios, number: 15, file: "15-my-agents", route: .agents),
        .init(platform: .ios, number: 16, file: "16-agent-profile", route: .agentProfile),
        .init(platform: .ios, number: 17, file: "17-schedules", route: .schedules),
        .init(platform: .ios, number: 18, file: "18-new-schedule", route: .createSchedule),
        .init(platform: .ios, number: 19, file: "19-computers", route: .devices),
        .init(platform: .ios, number: 20, file: "20-connect-computer", route: .pair),
        .init(platform: .ios, number: 21, file: "21-computer-offline", route: .offline),
        .init(platform: .ios, number: 22, file: "22-connections", route: .connections),
        .init(platform: .ios, number: 23, file: "23-settings", route: .settings),
        .init(platform: .ios, number: 24, file: "24-ai-models", route: .models),
        .init(platform: .ios, number: 25, file: "25-browser-view", route: .browser),
    ] + phoneOverview
    private static var phoneOverview: [Self] {
        #if os(iOS)
        [.init(platform: .ios, number: 26, file: "26-overview", route: .overview)]
        #else
        []
        #endif
    }
}
