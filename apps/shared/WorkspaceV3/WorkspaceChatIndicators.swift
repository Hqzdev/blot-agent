import BlotDesign
import SwiftUI

struct WorkspacePresenceDot: View {
    let online: Bool
    var size: CGFloat = 10
    var body: some View {
        if online {
            Circle().fill(Color.green).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(WorkspaceStyle.canvas, lineWidth: 1.5))
                .accessibilityHidden(true)
        }
    }
}

struct WorkspaceUnreadBadge: View {
    let count: Int
    var muted = false
    var size: CGFloat = 20
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        if count > 0 {
            Text(count, format: .number).font(.system(size: size * 0.58, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).padding(.horizontal, 6).frame(minWidth: size, minHeight: size)
                .background(muted ? WorkspaceStyle.secondary : Color.blue, in: Capsule())
                .contentTransition(.numericText()).animation(.easeOut(duration: 0.18), value: count)
                .accessibilityLabel(store.t("Unread messages") + ": \(count)")
        }
    }
}

struct WorkspaceTypingPreview: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        HStack(spacing: 4) {
            Text(store.t("Typing"))
            WorkspaceTypingIndicator(size: 3)
        }.foregroundStyle(WorkspaceStyle.secondary).lineLimit(1)
            .accessibilityElement(children: .ignore).accessibilityLabel(store.t("Agent is typing"))
    }
}

struct WorkspaceTypingIndicator: View {
    var size: CGFloat = 6
    var highlighted = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blotReduceMotion) private var reduceMotion

    private var active: Bool { !systemReduceMotion && !reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            HStack(spacing: size * 0.7) {
                ForEach(0..<3) { index in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) - Double(index) * 0.32
                    let pulse = active && phase >= 0 && phase < 0.64 ? sin(.pi * phase / 0.64) : 0
                    Circle().fill(highlighted ? Color(white: 0.55 + pulse * 0.45) : WorkspaceStyle.secondary)
                        .frame(width: size, height: size)
                        .scaleEffect(1 + pulse * 0.45)
                }
            }.frame(height: size * 2)
        }
        .accessibilityHidden(true)
    }
}
