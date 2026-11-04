import SwiftUI

/// One hero uses the existing choreography while keeping the agent's chosen silhouette and colour.
public struct WorkspaceAnimatedAvatar: View {
    let shape: WorkspaceAvatar.ShapeKind
    let color: Color
    let size: CGFloat
    @Environment(\.scenePhase) private var phase
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var director = BlotDirector()
    @State private var visible = false
    @State private var blinkStarted = Date()

    public init(shape: WorkspaceAvatar.ShapeKind = .round, color: Color = .primary, size: CGFloat = 68) {
        self.shape = shape; self.color = color; self.size = size
    }

    private var active: Bool { visible && phase == .active && !reduceMotion && !systemReduceMotion }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(director.actStart))
            WorkspaceAvatar(shape: shape, color: color, size: size,
                pose: active ? BlotMotion.pose(state: director.act, elapsed: elapsed, blink: blink(at: timeline.date), variant: director.variant) : BlotPose())
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: active) {
            guard active else { return }
            blinkStarted = Date()
            await director.run(.subtle, intro: false)
        }
        .accessibilityHidden(true)
    }

    private func blink(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(blinkStarted)).truncatingRemainder(dividingBy: 4.3)
        return elapsed < 0.24 ? abs(elapsed - 0.12) / 0.12 : 1
    }
}
