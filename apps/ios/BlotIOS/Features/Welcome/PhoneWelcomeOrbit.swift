import BlotDesign
import Foundation
import SwiftUI

struct PhoneWelcomeOrbit: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    @State private var startedAt = Date()

    private static let characters: [WelcomeOrbitCharacter] = [
        .init(shape: .tall, color: .init(red: 0.55, green: 0.28, blue: 1), x: 0.35, y: 0.07, size: 70, tilt: -18, motion: .doubleBlink),
        .init(shape: .cloud, color: .init(red: 0, green: 0.78, blue: 0.40), x: 0.71, y: 0.16, size: 86, tilt: 7, motion: .lookAround),
        .init(shape: .round, color: .init(red: 1, green: 0.59, blue: 0), x: 0.10, y: 0.25, size: 96, tilt: 8, motion: .nod),
        .init(shape: .round, color: .init(red: 1, green: 0.13, blue: 0.60), x: 1.01, y: 0.32, size: 64, tilt: -8, motion: .wink),
        .init(shape: .square, color: .init(red: 0.06, green: 0.49, blue: 1), x: -0.03, y: 0.45, size: 68, tilt: 8, motion: .curious),
        .init(shape: .round, color: .init(red: 0.55, green: 0.35, blue: 0.18), x: 1.04, y: 0.54, size: 72, tilt: -16, motion: .sway),
        .init(shape: .hexagon, color: .init(red: 1, green: 0.37, blue: 0), x: 0.06, y: 0.66, size: 92, tilt: -4, motion: .sleepy),
        .init(shape: .round, color: .init(red: 0, green: 0.69, blue: 0.63), x: 0.40, y: 0.76, size: 70, tilt: 13, motion: .bounce),
        .init(shape: .round, color: .init(red: 1, green: 0.13, blue: 0.24), x: 0.79, y: 0.71, size: 98, tilt: -5, motion: .peek)
    ]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: systemReduceMotion || reduceMotion || scenePhase != .active)) { timeline in
                let time = systemReduceMotion || reduceMotion ? 0 : timeline.date.timeIntervalSince(startedAt)
                let phase = time / 60 * 2 * .pi
                let scale = min(geometry.size.width / 393, 1.4)
                ZStack {
                    ForEach(Self.characters.indices, id: \.self) { index in
                        let character = Self.characters[index]
                        let dx = character.x - 0.5
                        let dy = character.y - 0.42
                        WelcomeOrbitFace(character: character, size: character.size * scale, pose: systemReduceMotion || reduceMotion ? .init() : character.motion.pose(at: time))
                            .rotationEffect(.degrees(character.tilt))
                            .position(
                                x: geometry.size.width * (0.5 + dx * cos(phase) - dy * 1.55 * sin(phase)),
                                y: geometry.size.height * (0.42 + dx / 1.55 * sin(phase) + dy * cos(phase))
                            )
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct WelcomeOrbitCharacter {
    let shape: WorkspaceAvatar.ShapeKind
    let color: Color
    let x: Double
    let y: Double
    let size: CGFloat
    let tilt: Double
    let motion: PhoneWelcomeAgentMotion
}

private struct WelcomeOrbitFace: View {
    let character: WelcomeOrbitCharacter
    let size: CGFloat
    let pose: PhoneWelcomeAgentMotion.Pose

    var body: some View {
        ZStack {
            WorkspaceAvatar(shape: character.shape, color: character.color, size: size, showsEyes: false)
            HStack(spacing: size * 0.13) {
                Capsule().frame(width: size * 0.115, height: size * 0.27)
                    .scaleEffect(y: pose.leftEye)
                Capsule().frame(width: size * 0.105, height: size * 0.25)
                    .scaleEffect(y: pose.rightEye)
            }
            .foregroundStyle(.white)
            .offset(x: size * pose.gazeX, y: size * (0.025 + pose.gazeY))
        }.frame(width: size, height: size)
            .scaleEffect(x: 1 / pose.stretch, y: pose.stretch)
            .rotationEffect(.degrees(pose.tilt))
            .offset(y: size * pose.lift)
    }
}
