import AppIntents
import Foundation

struct OpenApplePluginsIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть приложения Apple в Blot"
    static var description = IntentDescription("Открывает подключения системных приложений и разрешения агентов.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        #if os(macOS)
        let url = URL(string: "blot-agent-macos://apple-connections")!
        #else
        let url = URL(string: "blot-agent-ios://apple-connections")!
        #endif
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct BlotAppleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenApplePluginsIntent(), phrases: ["Открой подключения в \(.applicationName)"],
            shortTitle: "Приложения Apple", systemImageName: "app.connected.to.app.below.fill")
    }
}
