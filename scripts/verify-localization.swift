import Foundation

@main
struct LocalizationVerification {
    @MainActor static func main() {
        for tag in ["ru", "ru-RU", "ru_BY", "ru-KZ"] {
            precondition(WorkspaceLanguage.system(preferredLanguages: [tag]) == "ru", tag)
        }
        for tag in ["en", "en-US", "en-GB", "fr-FR", "de-DE", "zh-Hans", "uk-UA"] {
            precondition(WorkspaceLanguage.system(preferredLanguages: [tag, "ru-RU"]) == "en", tag)
        }
        precondition(WorkspaceLanguage.system(preferredLanguages: []) == "en")
        let suite = "blot.localization.verification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // The old forced-Russian default must not override automatic system selection.
        defaults.set("ru", forKey: "blot.v3.language")
        let preferences = WorkspaceLanguagePreferences(defaults: defaults)
        precondition(preferences.selection == "system")
        precondition(preferences.resolved == WorkspaceLanguage.system())
        preferences.selection = "ru"
        precondition(WorkspaceLanguagePreferences(defaults: defaults).resolved == "ru")
        preferences.selection = "en"
        precondition(WorkspaceLanguagePreferences(defaults: defaults).resolved == "en")
        preferences.selection = "system"
        precondition(preferences.resolved == WorkspaceLanguage.system())
        defaults.set("unknown", forKey: WorkspaceLanguagePreferences.defaultsKey)
        precondition(WorkspaceLanguagePreferences(defaults: defaults).selection == "system")
        let title = WorkspaceCopyTemplate(source: "Удалить «%@»?", translation: "Delete “%@”?")!
        precondition(title.translate("Удалить «My project 👋»?") == "Delete “My project 👋”?")
        precondition(title.translate("Unrelated user content") == nil)
        let counts = WorkspaceCopyTemplate(source: "%lld агентов · %lld групп", translation: "%lld agents · %lld groups")!
        precondition(counts.translate("12 агентов · 3 групп") == "12 agents · 3 groups")
        let reordered = WorkspaceCopyTemplate(source: "%@ of %@ tokens", translation: "%2$@ всего, %1$@ использовано")!
        precondition(reordered.translate("100 of 900 tokens") == "900 всего, 100 использовано")
        precondition(WorkspaceCopyTemplate(source: "Static", translation: "Статично") == nil)
        precondition(WorkspaceCopy.text("Settings", language: "ru") == "Настройки")
        precondition(WorkspaceCopy.text("Настройки", language: "en") == "Settings")
        precondition(WorkspaceCopy.text("Аккаунтов: 3", language: "en") == "Accounts: 3")
        precondition(WorkspaceCopy.text("Unknown user content 👋", language: "ru") == "Unknown user content 👋")
        precondition(WorkspaceCopy.text("Удалить «My file.md»?", language: "en") == "Delete “My file.md”?")
        print("Localization language selection, persistence and formatted text checks passed")
    }
}
