import BlotDesign
import SwiftUI

enum MacTeamSettingsStyle {
    static var sidebar: Color { BlotColor.dynamic(.init(light: 0xF7F7_F7FF, dark: 0x1212_12FF)) }
    static let accent = Color(red: 0.43, green: 0.41, blue: 0.88)
    static var canvas: Color { BlotColor.dynamic(.init(light: 0xFCFC_FCFF, dark: 0x1010_10FF)) }
    static var card: Color { BlotColor.dynamic(.init(light: 0xFFFF_FFFF, dark: 0x1919_19FF)) }
    static var edge: Color { BlotColor.dynamic(.init(light: 0xE7E7_E5FF, dark: 0x2B2B_2BFF)) }
}

struct MacTeamSettingsSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                if !title.isEmpty { Text(title).font(.system(size: 14, weight: .medium)) }
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .background(MacTeamSettingsStyle.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MacTeamSettingsStyle.edge))
        }
    }
}

struct MacTeamSettingsRow<Control: View>: View {
    @Environment(\.macCompactSettings) private var compact
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 24))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control.frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        }.padding(.vertical, 15).frame(minHeight: 60)
    }
}

struct MacTeamSettingsToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        MacTeamSettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(MacTeamSettingsStyle.accent)
                .accessibilityLabel(title)
        }
    }
}

struct MacTeamSettingsLink: View {
    let title: String
    var detail: String? = nil
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        MacTeamSettingsRow(title: title, detail: detail) {
            Button(actionTitle, action: action).buttonStyle(MacSettingsActionStyle())
        }
    }
}

struct MacTeamSettingsNavigationRow: View {
    let pane: MacTeamSettingsPane
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BlotIcon(pane.glyph, size: BlotIconSize.control)
                Text(pane.title).font(.system(size: 13, weight: .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(WorkspaceStyle.ink.opacity(selected ? 0.08 : hovered ? 0.035 : 0),
                            in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(BlotPlainButtonStyle()).focused($focused).focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(WorkspaceStyle.ink.opacity(focused ? 0.4 : 0)))
        .onHover { hovered = $0 }.kAnimation(KMotion.quick, value: hovered)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct MacSettingsActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(WorkspaceStyle.ink.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9)).opacity(enabled ? 1 : 0.4)
    }
}
