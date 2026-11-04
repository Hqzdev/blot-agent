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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: systemReduceMotion || reduceMotion || scenePhase != .active)) { timeline in
            HStack(spacing: size * 0.7) {
                ForEach(0..<3) { index in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.1 - Double(index) * 0.8
                    let pulse = systemReduceMotion || reduceMotion ? 0.5 : max(0, sin(phase))
                    Circle().fill(WorkspaceStyle.secondary).frame(width: size, height: size)
                        .opacity(0.4 + pulse * 0.6).offset(y: -CGFloat(pulse) * size * 0.5)
                }
            }.frame(height: size * 2)
        }
    }
}
