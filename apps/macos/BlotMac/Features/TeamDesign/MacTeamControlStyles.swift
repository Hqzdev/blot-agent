import BlotDesign
import SwiftUI

enum MacTeamStyle {
    static var sidebar: Color { BlotColor.dynamic(.init(light: 0xF7F7_F5FF, dark: 0x1717_17FF)) }
    static var settingsCanvas: Color { BlotColor.dynamic(.init(light: 0xF2F2_F7FF, dark: 0x1111_11FF)) }
    static var panel: Color { BlotColor.dynamic(.init(light: 0xFFFF_FFFF, dark: 0x2222_22FF)) }
    static var field: Color { BlotColor.dynamic(.init(light: 0xF1F1_EFFF, dark: 0x2929_29FF)) }
}

struct MacTeamNavigationButton<Label: View>: View {
    var selected = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.macTeamPressState) private var pressState

    var body: some View {
        Button {
            if let pressState { pressState.activate(action) }
            else { action() }
        } label: {
            label
                .foregroundStyle(WorkspaceStyle.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    WorkspaceStyle.ink.opacity(selected ? 0.08 : hovered ? 0.035 : 0),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BlotPlainButtonStyle())
        .focused($focused).focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WorkspaceStyle.ink.opacity(focused ? 0.45 : 0), lineWidth: 1)
        }
        .onHover { hovered = $0 }
        .kAnimation(KMotion.quick, value: hovered)
        .kAnimation(KMotion.standard, value: selected)
        .kAnimation(KMotion.quick, value: focused)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct MacTeamTextFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .focused($focused).focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(WorkspaceStyle.ink.opacity(focused ? 0.3 : 0), lineWidth: 1)
            }
            .kAnimation(KMotion.quick, value: focused)
    }
}

struct MacTeamSwitchStyle: ToggleStyle {
    var showsLabel = true

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 16) {
                if showsLabel {
                    configuration.label
                    Spacer(minLength: 8)
                }
                Capsule()
                    .fill(configuration.isOn ? BlotColor.inverse : WorkspaceStyle.ink.opacity(0.15))
                    .frame(width: 36, height: 22)
                    .overlay(alignment: .leading) {
                        Circle().fill(configuration.isOn ? BlotColor.onInverse : Color.white)
                            .frame(width: 18, height: 18).padding(2).offset(x: configuration.isOn ? 14 : 0)
                    }
            }.contentShape(Rectangle())
        }
        .buttonStyle(BlotPlainButtonStyle())
        .kAnimation(KMotion.standard, value: configuration.isOn)
        .accessibilityValue(configuration.isOn ? "Включено" : "Выключено")
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

struct MacTeamCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isOn ? BlotColor.inverse : MacTeamStyle.field)
                    .frame(width: 20, height: 20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(WorkspaceStyle.ink.opacity(configuration.isOn ? 0 : 0.2))
                    }
                    .overlay {
                        BlotIcon(.check, size: BlotIconSize.inline)
                            .foregroundStyle(BlotColor.onInverse).opacity(configuration.isOn ? 1 : 0)
                    }
                configuration.label
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(BlotPlainButtonStyle())
            .kAnimation(KMotion.quick, value: configuration.isOn)
            .accessibilityValue(configuration.isOn ? "Выбрано" : "Не выбрано")
            .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

extension View {
    func teamControls() -> some View {
        self.tint(BlotColor.inverse)
            .textFieldStyle(MacTeamTextFieldStyle())
            .toggleStyle(MacTeamSwitchStyle())
            .buttonStyle(WorkspaceButtonStyle(.secondary))
    }
}
