import BlotDesign
import SwiftUI

enum MacTeamSettingsStyle {
    static var canvas: Color { BlotColor.dynamic(.init(light: 0xFCFC_FCFF, dark: 0x1010_10FF)) }
    static var card: Color { BlotColor.dynamic(.init(light: 0xFFFF_FFFF, dark: 0x1919_19FF)) }
    static var edge: Color { BlotColor.dynamic(.init(light: 0xE7E7_E5FF, dark: 0x2B2B_2BFF)) }
}

struct MacTeamSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(WorkspaceStyle.secondary)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 18)
                .background(MacTeamSettingsStyle.card, in: RoundedRectangle(cornerRadius: BlotRadius.control))
                .overlay(RoundedRectangle(cornerRadius: BlotRadius.control).strokeBorder(MacTeamSettingsStyle.edge))
        }
    }
}

struct MacTeamSettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control
        }.padding(.vertical, 15).frame(minHeight: 60)
    }
}

struct MacTeamSettingsToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        MacTeamSettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).toggleStyle(MacTeamSwitchStyle(showsLabel: false))
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
            Button(actionTitle, action: action).buttonStyle(WorkspaceButtonStyle(.secondary))
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
                Text(pane.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(WorkspaceStyle.ink.opacity(selected ? 0.08 : hovered ? 0.035 : 0),
                            in: RoundedRectangle(cornerRadius: BlotRadius.control))
                .contentShape(RoundedRectangle(cornerRadius: BlotRadius.control))
        }
        .buttonStyle(BlotPlainButtonStyle()).focused($focused).focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: BlotRadius.control)
            .strokeBorder(WorkspaceStyle.ink.opacity(focused ? 0.4 : 0)))
        .onHover { hovered = $0 }.kAnimation(KMotion.quick, value: hovered)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
