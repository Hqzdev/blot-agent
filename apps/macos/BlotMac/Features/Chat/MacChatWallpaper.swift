import SwiftUI

/// Stores a design shared by both appearances so changing theme preserves the selection.
enum MacChatWallpaper: String, CaseIterable, Identifiable {
    case standard, notes, orbit, botanical, signal, postcards, ink, atmosphere

    static let defaultsKey = "blot.appearance.chatWallpaper"

    var id: String { rawValue }

    func assetName(for colorScheme: ColorScheme) -> String? {
        guard self != .standard else { return nil }
        let appearance = colorScheme == .dark ? "dark" : "light"
        return "ChatWallpaper-\(rawValue)-\(appearance)"
    }

    func title(russian: Bool) -> String {
        switch self {
        case .standard: russian ? "Стандартный" : "Default"
        case .notes: russian ? "Заметки" : "Notes"
        case .orbit: russian ? "Орбита" : "Orbit"
        case .botanical: russian ? "Ботаника" : "Botanical"
        case .signal: russian ? "Сигнал" : "Signal"
        case .postcards: russian ? "Открытки" : "Postcards"
        case .ink: russian ? "Чернила" : "Ink"
        case .atmosphere: russian ? "Атмосфера" : "Atmosphere"
        }
    }
}

struct MacChatWallpaperBackground: View {
    @AppStorage(MacChatWallpaper.defaultsKey) private var wallpaper: MacChatWallpaper = .standard

    var body: some View {
        MacChatWallpaperArtwork(wallpaper: wallpaper)
            .allowsHitTesting(false)
    }
}

struct MacChatWallpaperArtwork: View {
    let wallpaper: MacChatWallpaper
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let assetName = wallpaper.assetName(for: colorScheme) {
            GeometryReader { geometry in
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .accessibilityHidden(true)
        }
    }
}
