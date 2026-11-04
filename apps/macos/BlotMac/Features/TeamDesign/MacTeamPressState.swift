import SwiftUI

/// Read at activation time because a native button can queue its action before
/// SwiftUI has updated the enabled state after a hold.
@MainActor final class MacTeamPressState {
    private var menuOpen = false

    func beginMenu() { menuOpen = true }
    func endMenu() { menuOpen = false }

    func activate(_ action: () -> Void) {
        guard !menuOpen else { return }
        action()
    }
}

extension EnvironmentValues {
    @Entry var macTeamPressState: MacTeamPressState? = nil
}
