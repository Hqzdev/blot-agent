import BlotDesign
import SwiftUI

enum PhoneAgentAppearance {
    static let shapes: [WorkspaceAvatar.ShapeKind] = [.round, .oval, .square, .pill, .triangle, .hexagon, .cloud, .drop]
    static let colors = ["white", "brown", "red", "orange", "amber", "green", "teal", "blue", "purple", "pink", "gray", "ink"]
}

struct PhoneAgentPreview: View {
    let shape: WorkspaceAvatar.ShapeKind
    let color: String
    var size: CGFloat = 148
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: systemReduceMotion || reduceMotion || scenePhase != .active)) { timeline in
            let phase = systemReduceMotion || reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / 2
            ZStack {
                WorkspaceAvatar(shape: shape, color: WorkspaceAvatarView.color(color), size: size)
                    .id(shape).transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            .scaleEffect(1 + sin(phase) * 0.015)
            .rotationEffect(.degrees(sin(phase * 0.7) * 2))
            .animation(systemReduceMotion || reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.75), value: shape)
            .animation(systemReduceMotion || reduceMotion ? nil : .easeInOut(duration: 0.2), value: color)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
