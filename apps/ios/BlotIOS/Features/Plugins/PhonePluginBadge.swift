import BlotDesign
import SwiftUI

struct PhonePluginBadge: View {
    let connected: Bool
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        Text(connected ? store.t("Connected") : (store.language == "ru" ? "Установить" : "Install"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(connected ? BlotColor.dynamic(.init(light: 0x18623AFF, dark: 0x93E5B1FF)) : WorkspaceStyle.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(connected
                ? BlotColor.dynamic(.init(light: 0xE0F3E7FF, dark: 0x183826FF))
                : BlotColor.dynamic(.init(light: 0xF7F7F7FF, dark: 0x292929FF)), in: Capsule())
    }
}
