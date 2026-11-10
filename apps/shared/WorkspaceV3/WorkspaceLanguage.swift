import Foundation
import Observation

/// The first system language decides the fallback; region does not change the language.
enum WorkspaceLanguage {
    static func system(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard let first = preferredLanguages.first else { return "en" }
        return Locale(identifier: first).language.languageCode?.identifier == "ru" ? "ru" : "en"
    }
}

@Observable @MainActor
final class WorkspaceLanguagePreferences {
    static let defaultsKey = "blot.v3.languagePreference"
    private let defaults: UserDefaults?
    private var systemLanguage: String
    var selection: String {
        didSet { defaults?.set(selection, forKey: Self.defaultsKey) }
    }
    var resolved: String { ["en", "ru"].contains(selection) ? selection : systemLanguage }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        self.systemLanguage = WorkspaceLanguage.system()
        let saved = defaults?.string(forKey: Self.defaultsKey) ?? "system"
        self.selection = ["system", "en", "ru"].contains(saved) ? saved : "system"
    }

    func refreshSystemLanguage() { systemLanguage = WorkspaceLanguage.system() }
}
