import SwiftUI

/// Keeps the conversation usable as the chat list resizes.
struct MacWorkspaceLayout {
    static let minimumWidth: CGFloat = 640
    static let minimumHeight: CGFloat = 480
    let size: CGSize
    var preferredSidebarWidth: CGFloat? = nil
    static let minimumConversationWidth: CGFloat = 440

    static let defaultSidebarWidth: CGFloat = 344

    var sidebarWidth: CGFloat {
        let bounds = sidebarBounds(computerVisible: false)
        return min(bounds.upperBound, max(bounds.lowerBound, preferredSidebarWidth ?? Self.defaultSidebarWidth))
    }
    var supportsSidebar: Bool { size.width >= 900 }
    var popoverHeight: CGFloat { max(240, min(580, size.height - 100)) }

    func sidebarBounds(computerVisible: Bool) -> ClosedRange<CGFloat> {
        let contentMinimum = computerVisible
            ? MacBrowserSplitLayout.minimumChatWidth + MacBrowserSplitLayout.minimumBrowserWidth + MacBrowserSplitLayout.dividerWidth
            : Self.minimumConversationWidth
        return 220...max(220, min(480, size.width - contentMinimum - 4))
    }
}

private struct MacCompactSettingsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MacSheetSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 720, height: 650)
}

extension EnvironmentValues {
    var macCompactSettings: Bool {
        get { self[MacCompactSettingsKey.self] }
        set { self[MacCompactSettingsKey.self] = newValue }
    }
    var macSheetSize: CGSize {
        get { self[MacSheetSizeKey.self] }
        set { self[MacSheetSizeKey.self] = newValue }
    }
}

/// Measures the presenting window, so sheets also fit a small desktop window.
struct MacAdaptiveSheetHost: ViewModifier {
    @State private var size = MacSheetSizeKey.defaultValue

    func body(content: Content) -> some View {
        content.environment(\.macSheetSize, size)
            .onGeometryChange(for: CGSize.self) { geometry in
                CGSize(width: max(520, min(720, geometry.size.width - 32)),
                    height: max(360, min(650, geometry.size.height - 48)))
            } action: { size = $0 }
    }
}
