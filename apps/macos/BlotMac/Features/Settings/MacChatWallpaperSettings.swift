import BlotDesign
import SwiftUI

struct MacChatWallpaperSettings: View {
    @AppStorage(MacChatWallpaper.defaultsKey) private var wallpaper: MacChatWallpaper = .standard
    @Environment(\.macCompactSettings) private var compact
    @Environment(\.locale) private var locale

    private var russian: Bool { locale.language.languageCode?.identifier == "ru" }

    var body: some View {
        MacTeamSettingsSection(title: russian ? "Фон чатов" : "Chat background") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 2 : 4), spacing: 14) {
                ForEach(MacChatWallpaper.allCases) { option in
                    swatch(option)
                }
            }
            .padding(.vertical, 14)
        }
    }

    private func swatch(_ option: MacChatWallpaper) -> some View {
        let selected = wallpaper == option
        let title = option.title(russian: russian)
        let shape = RoundedRectangle(cornerRadius: BlotRadius.control)
        return Button {
            wallpaper = option
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(WorkspaceStyle.canvas)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay { MacChatWallpaperArtwork(wallpaper: option) }
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(selected ? WorkspaceStyle.ink : BlotColor.hairline, lineWidth: selected ? 2 : 1) }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WorkspaceStyle.canvas)
                                .frame(width: 18, height: 18)
                                .background(WorkspaceStyle.ink, in: Circle())
                                .padding(6)
                        }
                    }
                Text(verbatim: title).font(.system(size: 12)).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("workspace.chat-wallpaper.\(option.id)")
    }
}
