import SwiftUI

/// Keeps the conversation usable while retaining access to both auxiliary panels.
struct MacWorkspaceLayout {
    static let minimumWidth: CGFloat = 640
    static let minimumHeight: CGFloat = 480
    let size: CGSize

    var sidebarWidth: CGFloat { min(252, max(220, size.width * 0.22)) }
    var inspectorWidth: CGFloat { min(306, max(276, size.width * 0.24)) }
    var supportsSidebar: Bool { size.width >= 900 }
    var popoverHeight: CGFloat { max(240, min(580, size.height - 100)) }

    func supportsInspector(sidebarVisible: Bool) -> Bool {
        size.width - (sidebarVisible ? sidebarWidth : 0) - inspectorWidth >= 520
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
