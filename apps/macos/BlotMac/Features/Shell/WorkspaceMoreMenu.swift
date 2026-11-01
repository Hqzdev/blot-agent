import BlotDesign
import SwiftUI

struct WorkspaceMoreMenu: View {
    @Environment(AppState.self) private var app
    @State private var anchor = KMenuAnchor()
    @State private var presented = false

    var body: some View {
        Button(action: toggle) {
            KIcon("ellipsis", size: 20)
                .frame(width: K.railButtonSize, height: K.railButtonSize)
                .kHover(radius: K.rMd, active: presented)
        }
        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
        .help("More tools")
        .accessibilityLabel("More")
        .background(KMenuAnchorView(anchor: anchor))
        .onDisappear { if presented { KMenuController.shared.close() } }
        .onChange(of: app.currentUser) { _, _ in KMenuController.shared.close() }
    }

    private func toggle() {
        guard !presented, let view = anchor.view, let window = view.window else {
            KMenuController.shared.close()
            return
        }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        presented = true
        KMenuController.shared.showNavigation(WorkspaceMoreMenuCard().environment(app), beside: rect, in: window) {
            presented = false
        }
    }
}

struct WorkspaceMoreMenuCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ForEach(WorkspaceTool.allCases) { tool in
                WorkspaceMenuRow(title: tool.rawValue, icon: tool.icon) {
                    KMenuController.shared.close()
                    app.openTool(tool)
                }
            }
            ForEach(Array(app.pluginUsage.mostUsed(for: app.currentUser).prefix(3))) { plugin in
                WorkspaceMenuRow(title: plugin.name, icon: plugin.icon) {
                    guard let user = app.currentUser,
                          user.installedPlugins.contains(where: { $0.id == plugin.id }) else { return }
                    KMenuController.shared.close()
                    openURL(plugin.launchURL) { accepted in
                        if accepted { app.pluginUsage.recordOpening(plugin.id, for: user) }
                    }
                }
            }
        }
        .padding(6).frame(width: 230)
        .kPopover()
    }
}

private struct WorkspaceMenuRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                KIcon(icon, size: 16, color: K.text2)
                Text(title).font(KFont.ui(13)).foregroundStyle(K.text).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
            .kHover(radius: K.rMd)
        }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
    }
}
