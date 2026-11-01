//
//  ThemePreference.swift
//  BlotDesign
//
//  System / Light / Dark. Stored per device, never synced: each Mac and iPhone keeps its own
//  choice. Unknown or missing values fall back to System.
//

import SwiftUI

nonisolated public enum ThemePreference: String, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }
    public var title: String { rawValue }

    /// nil follows the system appearance.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// Local persistence for the theme choice.
nonisolated public enum ThemeStore {
    public static let defaultsKey = "blot.appearance.theme"

    public static func load(from defaults: UserDefaults = .standard) -> ThemePreference {
        defaults.string(forKey: defaultsKey).flatMap(ThemePreference.init(rawValue:)) ?? .system
    }

    public static func save(_ preference: ThemePreference, to defaults: UserDefaults = .standard) {
        if preference == .system {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(preference.rawValue, forKey: defaultsKey)
        }
    }
}

public extension View {
    /// Applies the theme to this view tree. Put it on every window root, sheet and popover host
    /// that is not a child of an already themed view (secondary windows, AppKit panels).
    func blotTheme(_ preference: ThemePreference) -> some View {
        preferredColorScheme(preference.colorScheme)
    }
}
