import BlotDesign
import Foundation

enum MacSettingsCatalog {
    struct Entry: Identifiable {
        let route: WorkspaceRoute
        let glyph: BlotGlyph
        let keywords: [String]
        var id: WorkspaceRoute { route }

        func matches(_ query: String, translate: (String) -> String) -> Bool {
            let text = ([route.title] + keywords).flatMap { [$0, translate($0)] }.joined(separator: " ")
            return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains(String($0)) }
        }
    }

    static let entries: [Entry] = [
        .init(route: .settings, glyph: .sliders, keywords: ["Language", "Show Blot in the menu bar", "Default model", "Run tasks on", "Keep working after closing the window"]),
        .init(route: .appearance, glyph: .sun, keywords: ["Theme", "System", "Light", "Dark", "Reduce Motion"]),
        .init(route: .notifications, glyph: .bell, keywords: ["Configure notifications", "Notifications need system permission. Phone reminders will work without a running computer."]),
        .init(route: .account, glyph: .person, keywords: ["Name", "Email", "Profile and security", "Sign-in method", "Delete account", "Sign out everywhere"]),
        .init(route: .models, glyph: .chip, keywords: ["API key", "Default model", "GigaChat", "OpenAI", "Anthropic", "Gemini", "xAI", "Compatible API"]),
        .init(route: .memory, glyph: .bookmark, keywords: ["Memory text", "Never remembered", "Source: conversation"]),
        .init(route: .permissions, glyph: .shieldCheck, keywords: ["Access mode", "Ask first", "Observe", "Trusted scope", "Allowed folders", "Send, publish and delete"]),
        .init(route: .permissionRules, glyph: .list, keywords: ["Create reports", "Read calendar", "Send email", "Run tests", "Revoke"]),
        .init(route: .connections, glyph: .plug, keywords: ["Gmail", "Yandex Mail", "Google Calendar", "Yandex Calendar", "Telegram", "Slack", "Notion", "GitHub", "Connect"]),
        .init(route: .mcp, glyph: .puzzle, keywords: ["Server name", "Server URL", "Transport", "Streamable HTTP", "stdio", "Add server"]),
        .init(route: .browserSettings, glyph: .globe, keywords: ["Chrome extension", "Allowed sites", "Pause on CAPTCHA, 2FA and sign-in", "Stop access"]),
        .init(route: .devices, glyph: .computer, keywords: ["Connect computer", "Pair a new device", "Online", "Offline", "Revoke"]),
        .init(route: .language, glyph: .language, keywords: ["Русский", "English"])
    ]

    static func glyph(for route: WorkspaceRoute) -> BlotGlyph {
        entries.first { $0.route == route }?.glyph ?? .sliders
    }

    static func glyph(forSetting title: String) -> BlotGlyph {
        switch title {
        case "Language": .language
        case "Show Blot in the menu bar", "Chrome extension": .layout
        case "Default model", "OpenAI", "Anthropic", "Gemini", "xAI", "Compatible API": .chip
        case "Run tasks on": .computer
        case "Ask before significant actions", "Pause on CAPTCHA, 2FA and sign-in": .shieldCheck
        case "Keep working after closing the window": .moon
        case "Name": .person
        case "Email", "Gmail", "Yandex Mail": .email
        case "Sign-in method": .lock
        case "Allowed folders": .folder
        case "Send, publish and delete": .share
        case "Google Calendar", "Yandex Calendar", "Read calendar": .calendar
        case "Telegram", "Slack": .chats
        case "Notion", "Create reports": .document
        case "GitHub", "Run tests": .code
        case "Allowed sites": .globe
        case "Send email": .send
        default: .sliders
        }
    }
}
