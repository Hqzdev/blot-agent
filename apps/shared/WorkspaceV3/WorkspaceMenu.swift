import BlotDesign
import SwiftUI

/// A transient Ori action list, independent of system menu and glass styling.
struct WorkspaceMenu<Actions: View, Label: View>: View {
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let label: () -> Label
    @State private var presented = false
    var body: some View {
        #if os(macOS)
        MacActionMenu(actions: actions, label: label)
        #else
        Button { presented.toggle() } label: {
            label().frame(minWidth: 44, minHeight: 44).contentShape(RoundedRectangle(cornerRadius: 14))
        }
            .buttonStyle(BlotPlainButtonStyle()).blotFocusRing()
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                WorkspaceMenuPanel(actions: actions, close: { presented = false })
            }
        #endif
    }
}

extension WorkspaceMenu where Label == BlotLabel {
    init(_ title: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.actions = actions
        self.label = { BlotLabel(title, symbol: "chevron.right") }
    }
}

#if os(iOS)
private struct WorkspaceMenuPanel<Actions: View>: View {
    @ViewBuilder let actions: () -> Actions
    let close: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Group(sections: actions().buttonStyle(WorkspaceMenuActionStyle(close: close)).labelStyle(.titleAndIcon)) { sections in
                    ForEach(sections) { section in
                        section.header.font(.caption.weight(.medium)).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, 12)
                        section.content
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.frame(width: 280).fixedSize(horizontal: false, vertical: true).frame(maxHeight: 440)
            .workspacePanelControls().labelStyle(.titleAndIcon)
            .background(WorkspaceStyle.canvas).presentationBackground(WorkspaceStyle.canvas)
            .presentationCornerRadius(22).presentationCompactAdaptation(.popover)
    }
}

extension View {
    func workspaceContextActions<Actions: View>(@ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(WorkspaceContextActions(actions: actions))
    }
}

private struct WorkspaceContextActions<Actions: View>: ViewModifier {
    @ViewBuilder let actions: () -> Actions
    @State private var presented = false
    func body(content: Content) -> some View {
        content.highPriorityGesture(LongPressGesture(minimumDuration: 0.45, maximumDistance: 12).onEnded { _ in presented = true })
            .accessibilityAction(named: Text("Open actions")) { presented = true }
            .sensoryFeedback(.selection, trigger: presented)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                WorkspaceMenuPanel(actions: actions, close: { presented = false })
            }
    }
}

private struct WorkspaceMenuActionStyle: PrimitiveButtonStyle {
    let close: () -> Void
    var size: BlotControlSize = .regular
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) { configuration.trigger(); close() } label: {
            configuration.label.font(.system(size: size == .compact ? 12 : 13))
                .foregroundStyle(configuration.role == .destructive ? .red : WorkspaceStyle.ink)
                .frame(maxWidth: .infinity, minHeight: size == .compact ? size.height : 44, alignment: .leading)
        }.buttonStyle(BlotButtonStyle(.ghost, size: size))
    }
}
#endif

#if os(macOS)
typealias WorkspaceFileActionsMenu = MacActionMenu
#else
typealias WorkspaceFileActionsMenu = Menu
#endif
