import BlotDesign
import SwiftUI

/// Role reactions settle into subtle idle motion instead of freezing the avatar.
struct AnimatedRoleAvatar: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let role: AgentRole
    var state: BlotState = .idle
    var size: CGFloat = 28
    @State private var settled = false
    var body: some View {
        BlotView(role: role, state: settled ? .idle : state, size: size, framing: .avatar, behavior: .subtle)
            .task(id: "\(state.rawValue)-\(phase)-\(app.settings.reduceMotion)-\(systemReduceMotion)") {
                settled = false
                guard phase == .active && !app.settings.reduceMotion && !systemReduceMotion else { return }
                guard [.happy, .wink, .jump].contains(state) else { return }
                do { try await Task.sleep(for: .seconds((state.duration ?? 0.5) + 0.9)) } catch { return }
                settled = true
            }
    }
}
