import SwiftUI

/// Shared timing for both Apple apps and their controls. Springs settle without bounce.
nonisolated public enum BlotInterfaceMotion {
    public enum Duration {
        public static let press = 0.12
        public static let quick = 0.15
        public static let standard = 0.22
        public static let panel = 0.28
    }
    public static let shift: CGFloat = 6
    public static let press = Animation.smooth(duration: Duration.press)
    public static let quick = Animation.smooth(duration: Duration.quick)
    public static let standard = Animation.smooth(duration: Duration.standard)
    public static let panel = Animation.smooth(duration: Duration.panel)
    public static let notice = standard
    public static let sidebar = panel
    public static let loading = Animation.easeOut(duration: 0.18)
}

private struct BlotReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var blotReduceMotion: Bool {
        get { self[BlotReduceMotionKey.self] }
        set { self[BlotReduceMotionKey.self] = newValue }
    }
}
