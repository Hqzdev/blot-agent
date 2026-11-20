import BlotDesign
import SwiftUI

struct PhoneTabIcon: View {
    enum Kind { case chats, calendar, overview, settings }

    let kind: Kind
    let activation: Int
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion
    #if DEBUG
    @Environment(\.phoneTabInteractionRecorder) private var recorder
    #endif

    private struct Frame {
        var travel = 0.0
        var tilt = 0.0
        var page = 0.0
        var rotation = 0.0
    }

    var body: some View {
        Group {
            if systemReduceMotion || reduceMotion { artwork(Frame()) }
            else {
                KeyframeAnimator(initialValue: Frame(), trigger: activation) { frame in
                    artwork(frame).transaction { $0.animation = nil }
                } keyframes: { current in
                    KeyframeTrack(\.travel) {
                        CubicKeyframe(-0.35, duration: 0.10)
                        CubicKeyframe(1, duration: 0.14)
                        CubicKeyframe(-1.2, duration: 0.16)
                        CubicKeyframe(0.28, duration: 0.14)
                        CubicKeyframe(-0.08, duration: 0.10)
                        CubicKeyframe(0, duration: 0.12)
                    }
                    KeyframeTrack(\.tilt) {
                        CubicKeyframe(-8, duration: 0.10)
                        CubicKeyframe(5, duration: 0.14)
                        CubicKeyframe(-4, duration: 0.16)
                        CubicKeyframe(1.5, duration: 0.14)
                        CubicKeyframe(0, duration: 0.22)
                    }
                    KeyframeTrack(\.page) {
                        CubicKeyframe(current.page.rounded(.down) + 2, duration: 0.76)
                    }
                    KeyframeTrack(\.rotation) {
                        CubicKeyframe(current.rotation + 360, duration: 0.76)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        #if DEBUG
        .onChange(of: activation) { _, sequence in recorder?.activatedIcon(kind, sequence: sequence) }
        #endif
    }

    private func artwork(_ frame: Frame) -> some View {
        ZStack {
            switch kind {
            case .chats:
                BlotIcon(.chats, size: 24)
                    .rotationEffect(.degrees(frame.tilt))
                    .offset(y: frame.travel)
            case .calendar:
                BlotIcon(symbol: "calendar", size: 24)
                calendarPage(turn: frame.page)
            case .overview:
                BlotIcon(.grid, size: 24)
                    .scaleEffect(1 + frame.travel * 0.05)
                    .rotationEffect(.degrees(frame.tilt))
            case .settings:
                BlotIcon(.settings, size: 24).rotationEffect(.degrees(frame.rotation))
            }
        }
        .frame(width: 24, height: 24)
        .environment(\.dynamicTypeSize, .large)
        .scaleEffect(size / 24)
        .frame(width: size, height: size)
    }

    private func calendarPage(turn: Double) -> some View {
        let phase = turn.truncatingRemainder(dividingBy: 1)
        let opacity = sin(.pi * min(phase / 0.58, 1))
        return ZStack {
            RoundedRectangle(cornerRadius: 1.5).stroke(lineWidth: 1.2)
            ForEach(0..<5, id: \.self) { index in
                Circle().frame(width: 1.4, height: 1.4)
                    .position(x: 4 + CGFloat(index % 3) * 4, y: index < 3 ? 3.5 : 7.5)
            }
        }
        .frame(width: 16, height: 10)
        .rotation3DEffect(.degrees(-180 * phase), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.35)
        .opacity(opacity)
        .position(x: 12, y: 15.5)
    }
}
