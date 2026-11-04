import BlotDesign
import Foundation
import SwiftUI

struct PhoneWelcomeOrbit: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    @State private var startedAt = Date()

    private static let characters: [WelcomeOrbitCharacter] = [
        .init(shape: .tall, color: .init(red: 0.55, green: 0.28, blue: 1), x: 0.35, y: 0.07, size: 70, tilt: -18),
        .init(shape: .cloud, color: .init(red: 0, green: 0.78, blue: 0.40), x: 0.71, y: 0.16, size: 86, tilt: 7),
        .init(shape: .round, color: .init(red: 1, green: 0.59, blue: 0), x: 0.10, y: 0.25, size: 96, tilt: 8),
        .init(shape: .round, color: .init(red: 1, green: 0.13, blue: 0.60), x: 1.01, y: 0.32, size: 64, tilt: -8),
        .init(shape: .square, color: .init(red: 0.06, green: 0.49, blue: 1), x: -0.03, y: 0.45, size: 68, tilt: 8),
        .init(shape: .round, color: .init(red: 0.55, green: 0.35, blue: 0.18), x: 1.04, y: 0.54, size: 72, tilt: -16),
        .init(shape: .hexagon, color: .init(red: 1, green: 0.37, blue: 0), x: 0.06, y: 0.66, size: 92, tilt: -4),
        .init(shape: .round, color: .init(red: 0, green: 0.69, blue: 0.63), x: 0.40, y: 0.76, size: 70, tilt: 13),
        .init(shape: .round, color: .init(red: 1, green: 0.13, blue: 0.24), x: 0.79, y: 0.71, size: 98, tilt: -5)
    ]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: systemReduceMotion || reduceMotion || scenePhase != .active)) { timeline in
                let time = systemReduceMotion || reduceMotion ? 0 : timeline.date.timeIntervalSince(startedAt)
                let phase = time / 240 * 2 * .pi
                let scale = min(geometry.size.width / 393, 1.4)
                ZStack {
                    ForEach(Self.characters.indices, id: \.self) { index in
                        let character = Self.characters[index]
                        let dx = character.x - 0.5
                        let dy = character.y - 0.42
                        let bob = time == 0 ? 0 : sin(time * 1.2 + Double(index)) * 3
                        WelcomeOrbitFace(character: character, size: character.size * scale, time: time, seed: Double(index))
                            .rotationEffect(.degrees(character.tilt + (time == 0 ? 0 : sin(time * 0.7 + Double(index)) * 6)))
                            .position(
                                x: geometry.size.width * (0.5 + dx * cos(phase) - dy * 1.55 * sin(phase)),
                                y: geometry.size.height * (0.42 + dx / 1.55 * sin(phase) + dy * cos(phase)) + bob
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
}

private struct WelcomeOrbitFace: View {
    let character: WelcomeOrbitCharacter
    let size: CGFloat
    let time: Double
    let seed: Double

    private var blink: Double {
        guard time > 0 else { return 1 }
        let moment = (time + seed * 0.83).truncatingRemainder(dividingBy: 5.2)
        return moment < 0.18 ? max(0.08, abs(moment - 0.09) / 0.09) : 1
    }

    var body: some View {
        ZStack {
            WorkspaceAvatar(shape: character.shape, color: character.color, size: size, showsEyes: false)
            HStack(spacing: size * 0.13) {
                Capsule().frame(width: size * 0.115, height: size * 0.27)
                Capsule().frame(width: size * 0.105, height: size * 0.25)
            }
            .foregroundStyle(.white).scaleEffect(x: 1, y: blink)
            .offset(x: time == 0 ? 0 : sin(time * 0.6 + seed) * size * 0.07, y: size * 0.025)
        }.frame(width: size, height: size)
    }
}
