import BlotDesign
import SwiftUI

enum PhoneSettingsStyle {
    static var canvas: Color { BlotColor.dynamic(.init(light: 0xF2F2F7FF, dark: 0x111111FF)) }
    static var row: Color { BlotColor.dynamic(.init(light: 0xFFFFFFFF, dark: 0x222222FF)) }
}

struct PhoneSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t(title)).font(.subheadline.weight(.semibold)).foregroundStyle(WorkspaceStyle.secondary)
                .padding(.horizontal, 18).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .background(PhoneSettingsStyle.row, in: RoundedRectangle(cornerRadius: 28))
        }
    }
}

struct PhoneSettingsRow: View {
    let title: String
    let symbol: String
    var detail: String?
    var value: String?
    var showsChevron = true
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            BlotIcon(symbol: symbol, size: 22).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.t(title)).font(.body)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.body).foregroundStyle(WorkspaceStyle.secondary) }
            if showsChevron { BlotIcon(.chevronRight, size: 12).foregroundStyle(WorkspaceStyle.secondary.opacity(0.5)) }
        }
        .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 54)
        .contentShape(Rectangle()).multilineTextAlignment(.leading)
    }
}

struct PhoneSettingsDivider: View {
    var body: some View { Divider().padding(.leading, 56).padding(.trailing, 18) }
}
