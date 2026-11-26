import Foundation
import Observation

/// Device-local recognition preference, independent from the interface and playback language.
@MainActor @Observable
final class WorkspaceVoicePreferences {
    static let defaultsKey = "blot.v3.voice.recognitionLanguage"
    static let followInterface = "interface"
    private let defaults: UserDefaults?
    var selection: String {
        didSet { defaults?.set(selection, forKey: Self.defaultsKey) }
    }
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        let saved = defaults?.string(forKey: Self.defaultsKey) ?? Self.followInterface
        selection = saved.isEmpty ? Self.followInterface : saved
    }
    func recognitionLocale(interfaceLanguage: String) -> Locale {
        Locale(identifier: selection == Self.followInterface ? (interfaceLanguage == "ru" ? "ru-RU" : "en-US") : selection)
    }
}
