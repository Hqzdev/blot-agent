import BlotDesign
import BlotDomain
import SwiftUI

/// A responding agent keeps its identity while its eyes and silhouette move gently.
struct WorkspaceThinkingAvatar: View {
    let agent: BlotV3.AgentProfile
    var size: CGFloat = 24
    var state: BlotState = .thinking
    @Environment(\.scenePhase) private var phase
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var visible = false
    @State private var started = Date()
    private var active: Bool { visible && phase == .active && !reduceMotion && !systemReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !active)) { context in
            let elapsed = active ? max(0, context.date.timeIntervalSince(started)) : BlotMotion.restingTime
            let cycle = elapsed.truncatingRemainder(dividingBy: 3.6)
            let blink = active && cycle < 0.22 ? abs(cycle - 0.11) / 0.11 : 1
            WorkspaceAvatar(shape: .init(rawValue: agent.avatarShape) ?? .round,
                color: WorkspaceAvatarView.color(agent.avatarColor), size: size,
                pose: BlotMotion.pose(state: state, elapsed: elapsed, blink: blink))
        }.onAppear { started = Date(); visible = true }.onDisappear { visible = false }
            .onChange(of: state) { _, _ in started = Date() }
            .accessibilityHidden(true)
    }
}
