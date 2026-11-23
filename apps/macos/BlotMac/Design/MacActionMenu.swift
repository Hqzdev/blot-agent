import BlotDesign
import SwiftUI

/// The same action list fits short command menus and scrolls long option lists.
struct MacActionMenuPanel<Content: View>: View {
    var width: CGFloat = 236
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows.fixedSize(horizontal: false, vertical: true)
            ScrollView { rows }
        }
        .frame(width: width)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 13))
        .foregroundStyle(WorkspaceStyle.ink)
        .background(WorkspaceStyle.canvas)
        .presentationBackground(WorkspaceStyle.canvas)
        .presentationCornerRadius(16)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 1, content: content)
            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .labelStyle(MenuLabelStyle())
                .font(.system(size: 13))
                .foregroundStyle(configuration.role == .destructive ? Color.red : WorkspaceStyle.ink)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 29, alignment: .leading)
                .background(WorkspaceStyle.ink.opacity(enabled && (hovered || configuration.isPressed) ? 0.075 : 0),
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .opacity(enabled ? 1 : 0.45)
        }
    }

    private struct MenuLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 9) {
                configuration.icon.frame(width: 18)
                configuration.title
            }
        }
    }
}

struct MacMenuDismissStyle: PrimitiveButtonStyle {
    let close: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) { close(); configuration.trigger() } label: { configuration.label }
            .buttonStyle(MacMenuRowStyle())
    }
}

struct MacActionMenu<Actions: View, Label: View>: View {
    var edge: Edge = .bottom
    var isSubmenu = false
    var width: CGFloat = 236
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let label: () -> Label
    @State private var presented = false

    var body: some View {
        Group {
            if isSubmenu { trigger.buttonStyle(MacMenuRowStyle()) }
            else { trigger.buttonStyle(.plain) }
        }
        .popover(isPresented: $presented, arrowEdge: edge) {
            MacActionMenuPanel(width: width) { actions().buttonStyle(MacMenuDismissStyle(close: { presented = false })) }
        }
    }

    private var trigger: some View {
        Button { presented.toggle() } label: { label().contentShape(Rectangle()) }
    }
}

extension View {
    func macCommandMenu<Actions: View>(@ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(MacTeamPressMenu(secondaryClick: true, preservesTap: true, surface: .sidebar) { close in
            actions().buttonStyle(MacMenuDismissStyle(close: close))
        })
    }
}
