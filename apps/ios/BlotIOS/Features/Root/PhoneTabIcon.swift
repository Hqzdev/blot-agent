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
                PhoneChatIconBubble(rear: true).stroke(style: stroke)
                    .rotationEffect(.degrees(-frame.tilt), anchor: .init(x: 0.65, y: 0.65))
                    .offset(x: -frame.travel * 1.2, y: frame.travel * 1.6)
                PhoneChatIconBubble(rear: false).stroke(style: stroke)
                    .rotationEffect(.degrees(frame.tilt), anchor: .init(x: 0.4, y: 0.4))
                    .offset(x: frame.travel * 1.2, y: -frame.travel * 1.6)
            case .calendar:
                BlotIcon(symbol: "calendar", size: 24)
                calendarPage(turn: frame.page)
            case .overview:
                ForEach(0..<4, id: \.self) { index in
                    let x: CGFloat = index % 2 == 0 ? 1 : -1
                    let y: CGFloat = index < 2 ? 1 : -1
                    RoundedRectangle(cornerRadius: 2).stroke(style: stroke)
                        .frame(width: 7, height: 7)
                        .rotationEffect(.degrees(frame.tilt * Double(x * y) * 0.7))
                        .position(x: x > 0 ? 6.5 : 17.5, y: y > 0 ? 6.5 : 17.5)
                        .offset(x: frame.travel * 2 * x, y: frame.travel * 2 * y)
                }
            case .settings:
                BlotIcon(.settings, size: 24).rotationEffect(.degrees(frame.rotation))
            }
        }
        .frame(width: 24, height: 24)
        .environment(\.dynamicTypeSize, .large)
        .scaleEffect(size / 24)
        .frame(width: size, height: size)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round) }

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

private nonisolated struct PhoneChatIconBubble: Shape {
    let rear: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if rear {
            path.move(to: .init(x: 18, y: 8))
            path.addLine(to: .init(x: 19, y: 8))
            path.addCurve(to: .init(x: 22, y: 11), control1: .init(x: 20.66, y: 8), control2: .init(x: 22, y: 9.34))
            path.addLine(to: .init(x: 22, y: 21))
            path.addLine(to: .init(x: 17, y: 18))
            path.addLine(to: .init(x: 12, y: 18))
            path.addCurve(to: .init(x: 9, y: 15), control1: .init(x: 10.34, y: 18), control2: .init(x: 9, y: 16.66))
        } else {
            path.move(to: .init(x: 5, y: 3))
            path.addLine(to: .init(x: 15, y: 3))
            path.addCurve(to: .init(x: 18, y: 6), control1: .init(x: 16.66, y: 3), control2: .init(x: 18, y: 4.34))
            path.addLine(to: .init(x: 18, y: 12))
            path.addCurve(to: .init(x: 15, y: 15), control1: .init(x: 18, y: 13.66), control2: .init(x: 16.66, y: 15))
            path.addLine(to: .init(x: 8, y: 15))
            path.addLine(to: .init(x: 3, y: 18))
            path.addLine(to: .init(x: 3, y: 6))
            path.addCurve(to: .init(x: 5, y: 3), control1: .init(x: 3, y: 4.6), control2: .init(x: 3.6, y: 3.4))
            path.closeSubpath()
        }
        return path.applying(.init(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
