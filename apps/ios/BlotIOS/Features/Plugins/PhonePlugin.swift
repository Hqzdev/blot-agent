import Foundation

struct PhonePlugin: Identifiable {
    enum Section: String, CaseIterable { case featured = "Featured", team = "Team plugins" }
    let name: String
    let description: String
    let asset: String
    let section: Section
    let scopes: [String]
    var id: String { name }

    static let all: [Self] = [
        .init(name: "Gmail", description: "Search, read, draft, and manage email", asset: "PluginGmail", section: .featured, scopes: ["mail.read", "mail.draft"]),
        .init(name: "Google Calendar", description: "Search events and schedule meetings", asset: "PluginCalendar", section: .featured, scopes: ["calendar.read", "calendar.write"]),
        .init(name: "Google Drive", description: "Search, read, create, and share files", asset: "PluginDrive", section: .featured, scopes: ["files.read", "files.write"]),
        .init(name: "Granola", description: "Your meetings in your workflow. Access your team’s notes.", asset: "PluginGranola", section: .featured, scopes: ["notes.read"]),
        .init(name: "Loom", description: "Record and share video updates with your team", asset: "PluginLoom", section: .team, scopes: ["videos.read", "videos.create"]),
        .init(name: "1Password", description: "Share a dedicated vault with your agents through a service account", asset: "Plugin1Password", section: .team, scopes: ["vault.read"])
    ]
}
