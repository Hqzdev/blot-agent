import BlotDesign
import SwiftUI

enum MacTeamSettingsStyle {
    static var sidebar: Color { MacChatStyle.sidebar }
    static let accent = Color(red: 0.43, green: 0.41, blue: 0.88)
    static var canvas: Color { WorkspaceStyle.canvas }
    static var card: Color { BlotColor.panel }
    static var edge: Color { BlotColor.hairline }
}

struct MacTeamSettingsSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                if !title.isEmpty { WorkspaceLocalizedText(title).font(.system(size: 14, weight: .medium)) }
                if let detail { WorkspaceLocalizedText(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .background(MacTeamSettingsStyle.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MacTeamSettingsStyle.edge))
        }
    }
}

struct MacTeamSettingsRow<Control: View>: View {
    var localizesTitle = true
    @Environment(\.macCompactSettings) private var compact
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 24))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if localizesTitle { WorkspaceLocalizedText(title) }
                    else { Text(title) }
                }.font(.system(size: 13))
                if let detail {
                    WorkspaceLocalizedText(detail).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary).lineSpacing(3)
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
    @Environment(\.locale) private var locale
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                WorkspaceLocalizedText(title).font(.system(size: 13))
                if let detail {
                    WorkspaceLocalizedText(detail).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(BlotToggleStyle())
            .accessibilityLabel(WorkspaceCopy.text(title, language: locale.language.languageCode?.identifier ?? "en"))
            .padding(.vertical, 8).frame(minHeight: 60)
    }

}

struct MacTeamSettingsLink: View {
    let title: String
    var detail: String? = nil
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        MacTeamSettingsRow(title: title, detail: detail) {
            Button(LocalizedStringKey(actionTitle), action: action).buttonStyle(MacSettingsActionStyle())
        }
    }
}

struct MacTeamSettingsNavigationRow: View {
    let pane: MacTeamSettingsPane
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BlotIcon(pane.glyph, size: BlotIconSize.control)
                WorkspaceLocalizedText(pane.title).font(.system(size: 13, weight: .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(WorkspaceStyle.ink.opacity(selected ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(BlotPlainButtonStyle(hoverIn: RoundedRectangle(cornerRadius: 14))).focused($focused).focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(WorkspaceStyle.ink.opacity(focused ? 0.4 : 0)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct MacSettingsActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BlotButtonStyle(.secondary, size: .large).makeBody(configuration: configuration)
    }
}
