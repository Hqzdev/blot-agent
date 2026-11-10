import Foundation

enum PhoneSettingsCatalog {
    struct Item: Identifiable {
        let route: WorkspaceRoute
        let title: String
        let detail: String
        let symbol: String
        let group: String
        var id: WorkspaceRoute { route }
    }
    static let groups = ["Workspace", "Personal", "Integrations"]
    static let items: [Item] = [
        .init(route: .files, title: "Files", detail: "Workspace files, attachments and agent results.", symbol: "folder", group: "Workspace"),
        .init(route: .appSettings, title: "General", detail: "App language and permissions.", symbol: "gearshape", group: "Personal"),
        .init(route: .notifications, title: "Notifications", detail: "Events your agents notify you about.", symbol: "bell", group: "Personal"),
        .init(route: .settingsProfile, title: "Profile", detail: "Your profile, token activity and account actions.", symbol: "person.crop.circle", group: "Personal"),
        .init(route: .appearance, title: "Appearance", detail: "Theme, motion and interface density.", symbol: "sun.max", group: "Personal"),
        .init(route: .personalization, title: "Personalization", detail: "Response preferences and defaults for new agents.", symbol: "slider.horizontal.3", group: "Personal"),
        .init(route: .memory, title: "Agent memory", detail: "Shared context and memories of individual agents.", symbol: "brain", group: "Workspace"),
        .init(route: .settingsStorage, title: "Files and data", detail: "Local documents and conversations.", symbol: "internaldrive", group: "Workspace"),
        .init(route: .permissions, title: "Data and privacy", detail: "Data storage and agent permissions.", symbol: "checkmark.shield", group: "Workspace"),
        .init(route: .devices, title: "Computers", detail: "Devices connected to your workspace.", symbol: "desktopcomputer", group: "Workspace"),
        .init(route: .connections, title: "Applications", detail: "Your services and accounts for the team.", symbol: "puzzlepiece.extension", group: "Integrations"),
        .init(route: .mcp, title: "MCP servers", detail: "External tools for your agents.", symbol: "network", group: "Integrations"),
        .init(route: .models, title: "AI models", detail: "Models and provider connections.", symbol: "cpu", group: "Integrations"),
        .init(route: .settingsUpdates, title: "Updates", detail: "Installed application version.", symbol: "arrow.down.circle", group: "Integrations"),
    ]
    static func title(for route: WorkspaceRoute) -> String? {
        if [.account, .usage].contains(route) { return "Profile" }
        return items.first { $0.route == route }?.title
    }
}

enum PhoneSettingsPreferenceKey {
    static let compactMessages = "blot.ios.compactMessages"
    static let defaultRole = "blot.ios.defaultAgentRole"
    static let defaultInstructions = "blot.ios.defaultAgentInstructions"
}

@MainActor
extension WorkspaceStore {
    func settingsText(_ text: String) -> String {
        language == "ru" ? PhoneSettingsCopy.russian[text] ?? t(text) : text
    }
}
