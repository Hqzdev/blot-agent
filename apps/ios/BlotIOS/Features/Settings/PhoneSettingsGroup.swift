import BlotDesign
import SwiftUI

enum PhoneSettingsStyle {
    static var canvas: Color { WorkspaceStyle.canvas }
    static var row: Color { BlotColor.dynamic(.init(light: 0xFFFFFFFF, dark: 0x191919FF)) }
    static var edge: Color { BlotColor.dynamic(.init(light: 0xE7E7E5FF, dark: 0x2B2B2BFF)) }
    static let accent = Color(red: 0.43, green: 0.41, blue: 0.88)
    static let radius = PhonePageLayout.radius
}

struct PhoneSettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        PhonePage { content }
        .tint(PhoneSettingsStyle.accent)
    }
}

struct PhoneSettingsGroup<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty || detail != nil {
                VStack(alignment: .leading, spacing: 7) {
                    if !title.isEmpty {
                        Text(store.settingsText(title)).font(.subheadline.weight(.medium)).accessibilityAddTraits(.isHeader)
                    }
                    if let detail {
                        Text(store.settingsText(detail)).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .background(PhoneSettingsStyle.row, in: RoundedRectangle(cornerRadius: PhoneSettingsStyle.radius))
                .overlay(RoundedRectangle(cornerRadius: PhoneSettingsStyle.radius).strokeBorder(PhoneSettingsStyle.edge))
        }
    }
}

struct PhoneSettingsRow: View {
    let title: String
    var symbol = ""
    var detail: String?
    var value: String?
    var showsChevron = true
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            if !symbol.isEmpty { BlotIcon(symbol: symbol, size: 20).frame(width: 24).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 5) {
                Text(store.settingsText(title)).font(.subheadline)
                if let detail { Text(store.settingsText(detail)).font(.footnote).foregroundStyle(WorkspaceStyle.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let value { Text(value).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary).multilineTextAlignment(.trailing) }
            if showsChevron { BlotIcon(.chevronRight, size: 11).foregroundStyle(WorkspaceStyle.secondary.opacity(0.6)) }
        }
        .padding(.horizontal, 16).padding(.vertical, 15).frame(minHeight: 56)
        .contentShape(Rectangle()).multilineTextAlignment(.leading)
    }
}

struct PhoneSettingsValueRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.settingsText(title)).font(.subheadline)
                if let detail {
                    Text(store.settingsText(detail)).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control.font(.subheadline).tint(PhoneSettingsStyle.accent)
        }.padding(.horizontal, 16).padding(.vertical, 15).frame(minHeight: 56)
    }
}

struct PhoneSettingsToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        PhoneSettingsValueRow(title: title, detail: detail) {
            Toggle(store.settingsText(title), isOn: $isOn).labelsHidden().tint(PhoneSettingsStyle.accent)
                .accessibilityLabel(store.settingsText(title))
        }
    }
}

struct PhoneSettingsDivider: View {
    var body: some View { Rectangle().fill(PhoneSettingsStyle.edge).frame(height: 0.5).padding(.horizontal, 16).accessibilityHidden(true) }
}
