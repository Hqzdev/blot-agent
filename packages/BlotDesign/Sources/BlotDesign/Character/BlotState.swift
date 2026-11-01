//
//  BlotState.swift
//  BlotDesign
//
//  Blot's moods, the pose of a single frame and the keyframed motion that produces it.
//  Pure values: no app state, no platform types. Coordinates are in the 120 × 100 body box.
//

import Foundation

/// Agent-driven states come first, then the ambient beats `BlotDirector` plays on its own.
nonisolated public enum BlotState: String, CaseIterable, Identifiable, Sendable {
    // Agent-driven
    case idle, planning, thinking, working, waiting, happy, wink, jump, error, blocked, sleep, wakeUp, peek
    // Ambient beats
    case glance, curious, wiggle, bounce, nod, stretch, doze, peekaboo, listening

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .planning: "Look around"
        case .jump: "Hop"
        case .waiting: "Waiting for you"
        case .wakeUp: "Wake up"
        case .peek: "Peek in"
        case .bounce: "Double hop"
        case .peekaboo: "Peekaboo"
        case .listening: "Listening"
        default: rawValue.capitalized
        }
    }

    /// One-shot motions stop after this many seconds; loops return nil.
    public var duration: Double? {
        switch self {
        case .happy: 0.36
        case .wink: 0.52
        case .jump: 0.64
        case .error: 0.42
        case .wakeUp: 0.3
        case .peek: 0.56
        case .glance: 1.5
        case .curious: 1.6
        case .wiggle: 0.95
        case .bounce: 1.25
        case .nod: 0.85
        case .stretch: 1.9
        case .doze: 2.8
        case .peekaboo: 1.7
        default: nil
        }
    }

    /// Big, eye-catching beats — the director spaces them out so Blot never looks frantic.
    public var isBig: Bool { [.happy, .jump, .bounce, .wiggle, .peekaboo].contains(self) }

    /// States that describe a problem or a request; reactions never cover them.
    public var isAttention: Bool { [.waiting, .blocked, .error].contains(self) }
}

/// Everything that changes between frames. Units are the 120 × 100 body box.
nonisolated public struct BlotPose: Sendable, Equatable {
    public var x = 0.0
    public var y = 0.0
    public var scaleX = 1.0
    public var scaleY = 1.0
    /// Lean around the bottom centre, degrees (positive = clockwise).
    public var tilt = 0.0
    /// Where Blot looks: (1, 0) right — the default from the icon — (0, -1) up, (0, 0) blank stare.
    public var gazeX = 1.0
    public var gazeY = 0.0
    public var openL = 1.0
    public var openR = 1.0
    public var happyL = false
    public var happyR = false
    public var big = 0.0
    public var sad = false
    public var cross = false
    public var ember = 0.0
    public var bang = false
    public var dots = 0
    public var sweat = false
    public var sparks = false
    public var asleep = false

    public init() {}
}

/// Timing follows the keyframes in agent.pen. `variant` (0…1) picks the direction of
/// glances and the side of a curious tilt, so repeated beats never look identical.
nonisolated public enum BlotMotion {
    /// Elapsed time used when motion is reduced: every one-shot has finished, so the pose is the
    /// state's resting expression and nothing moves.
    public static let restingTime: Double = 10

    public static func pose(state: BlotState, elapsed t: Double, blink: Double = 1, variant: Double = 0) -> BlotPose {
        var p = BlotPose()
        p.openL = blink; p.openR = blink
        let breathe = sin(t * .pi * 2 / 3.2)
        switch state {
        case .idle:
            p.scaleY = 1 + 0.02 * breathe
            p.scaleX = 1 - 0.006 * breathe
            p.x = 1.2 * sin(t * .pi * 2 / 5.3)
            p.tilt = 0.8 * sin(t * .pi * 2 / 6.8)
            p.gazeX = 0.6 + 0.35 * sin(t * .pi * 2 / 4.6)
            p.gazeY = 0.2 * sin(t * .pi * 2 / 5.7)
        case .planning:
            let l = t.truncatingRemainder(dividingBy: 2.4)
            p.gazeX = lerp(l, [(0, 1), (0.6, 0), (1.2, -1), (1.8, 0), (2.4, 1)])
            p.gazeY = lerp(l, [(0, 0), (0.6, -1), (1.2, 0), (1.8, 1), (2.4, 0)])
        case .thinking:
            let l = t.truncatingRemainder(dividingBy: 1.5)
            p.gazeX = 0.2; p.gazeY = -1
            p.dots = min(3, Int(l / 0.3))
            p.scaleY = 1 + 0.02 * breathe
        case .working:
            let l = t.truncatingRemainder(dividingBy: 1.2)
            p.gazeX = lerp(l, [(0, 0), (0.3, -1), (0.6, 0), (0.9, 1), (1.2, 0)])
            p.gazeY = lerp(l, [(0, 1), (0.3, 0), (0.6, 1), (0.9, 0), (1.2, 1)])
            p.ember = 0.35 + 0.65 * (1 + cos(t * .pi * 2 / 1.2)) / 2
            p.scaleY = lerp(l, [(0, 1), (0.6, 0.97), (1.2, 1)])
        case .waiting:
            let l = t.truncatingRemainder(dividingBy: 1.6)
            p.bang = true
            p.gazeX = 0; p.gazeY = -1
            p.big = lerp(l, [(0, 0), (0.2, 1), (1.2, 1), (1.6, 0)])
            p.y = lerp(l, [(0, 0), (0.2, 0), (0.5, -8), (0.8, 0), (1.6, 0)])
            p.scaleX = lerp(l, [(0, 1), (0.5, 0.96), (0.8, 1.06), (1.0, 1)])
            p.scaleY = lerp(l, [(0, 1), (0.5, 1.06), (0.8, 0.94), (1.0, 1)])
        case .happy:
            p.big = lerp(t, [(0, 0), (0.09, 1), (0.2, 0)])
            p.happyL = t > 0.14; p.happyR = t > 0.14
            p.scaleY = lerp(t, [(0, 1), (0.2, 1.08), (0.36, 1)])
            p.y = lerp(t, [(0, 0), (0.2, -4), (0.36, 0)])
            p.sparks = t > 0.14 && t < 0.9
        case .wink:
            p.openR = lerp(t, [(0, 1), (0.12, 0.5), (0.2, 0.2), (0.42, 0.2), (0.52, 1)])
            p.happyR = t > 0.18 && t < 0.46
            p.scaleY = lerp(t, [(0, 1), (0.2, 1.03), (0.42, 1.03), (0.52, 1)])
            p.tilt = lerp(t, [(0, 0), (0.2, 4), (0.42, 4), (0.52, 0)])
        case .jump:
            p.scaleX = lerp(t, [(0, 1), (0.08, 1.14), (0.16, 0.9), (0.4, 1), (0.48, 1.12), (0.64, 1)])
            p.scaleY = lerp(t, [(0, 1), (0.08, 0.84), (0.16, 1.12), (0.4, 1), (0.48, 0.86), (0.64, 1)])
            p.y = lerp(t, [(0, 0), (0.08, 0), (0.16, -10), (0.28, -26), (0.4, -6), (0.48, 0), (0.64, 0)])
            p.happyL = t > 0.2; p.happyR = t > 0.2
        case .error:
            p.cross = t > 0.04 && t < 0.38
            p.sad = t >= 0.38
            p.sweat = t >= 0.38
            p.x = lerp(t, [(0, 0), (0.06, 0), (0.16, -5), (0.26, 5), (0.34, -2), (0.42, 0)])
            p.scaleX = lerp(t, [(0, 1), (0.06, 1.08), (0.16, 1), (0.42, 1)])
            p.scaleY = lerp(t, [(0, 1), (0.06, 0.92), (0.16, 1), (0.42, 0.94)])
        case .blocked:
            let l = t.truncatingRemainder(dividingBy: 3)
            p.sad = !(l > 0.9 && l < 1.8)
            p.openL = min(blink, 0.55); p.openR = min(blink, 0.55)
            p.gazeX = lerp(l, [(0, 0), (1.0, -1), (1.5, 1), (2.2, 0), (3, 0)])
            p.gazeY = 0.6
            p.scaleY = 0.95 + 0.015 * breathe
        case .sleep:
            p.openL = 0; p.openR = 0
            p.asleep = true
            p.scaleY = 1 + 0.03 * breathe
        case .wakeUp:
            p.big = lerp(t, [(0, 0), (0.08, 1), (0.16, 1), (0.24, 0)])
            p.openL = lerp(t, [(0, 0), (0.08, 1), (0.2, 1), (0.24, 0.4), (0.3, 1)])
            p.openR = p.openL
            p.gazeX = t < 0.24 ? 0 : 1
            p.scaleY = lerp(t, [(0, 1), (0.08, 1.12), (0.16, 0.97), (0.3, 1)])
            p.y = lerp(t, [(0, 0), (0.08, -6), (0.16, 0)])
        case .peek:
            p.y = lerp(t, [(0, 100), (0.14, 60), (0.28, 28), (0.42, -6), (0.56, 0)])
            p.openL = lerp(t, [(0, 0), (0.28, 0.5), (0.42, 1)])
            p.openR = p.openL
            p.scaleY = lerp(t, [(0, 1), (0.42, 1.06), (0.56, 1)])

        // MARK: Ambient beats
        case .glance:
            // Eight directions, never straight back at the default «right».
            let angle = (0.125 + variant * 0.75) * 2 * .pi
            let k = lerp(t, [(0, 0), (0.12, 1), (1.3, 1), (1.5, 0)])
            p.gazeX = 1 + (cos(angle) - 1) * k
            p.gazeY = sin(angle) * 0.9 * k
            p.scaleY = 1 + 0.012 * breathe
        case .curious:
            let side = variant < 0.5 ? -1.0 : 1.0
            p.tilt = lerp(t, [(0, 0), (0.25, 8 * side), (1.3, 8 * side), (1.6, 0)])
            p.gazeX = lerp(t, [(0, 1), (0.25, side), (1.3, side), (1.6, 1)])
            p.gazeY = lerp(t, [(0, 0), (0.25, -0.35), (1.3, -0.35), (1.6, 0)])
            p.big = lerp(t, [(0, 0), (0.25, 0.35), (1.3, 0.35), (1.6, 0)])
            p.scaleY = lerp(t, [(0, 1), (0.25, 1.03), (1.6, 1)])
        case .wiggle:
            let envelope = lerp(t, [(0, 0), (0.1, 1), (0.75, 1), (0.95, 0)])
            p.tilt = 7 * sin(t * .pi * 2 * 3.2) * envelope
            p.scaleY = 1 + 0.035 * abs(sin(t * .pi * 2 * 3.2)) * envelope
            p.happyL = t > 0.06 && t < 0.9; p.happyR = p.happyL
        case .bounce:
            p.y = lerp(t, [(0, 0), (0.08, 0), (0.2, -18), (0.32, 0), (0.4, 0), (0.52, -10), (0.64, 0), (1.25, 0)])
            p.scaleX = lerp(t, [(0, 1), (0.08, 1.1), (0.16, 0.94), (0.3, 1), (0.34, 1.1), (0.42, 1), (0.64, 1.06), (0.76, 1)])
            p.scaleY = lerp(t, [(0, 1), (0.08, 0.88), (0.16, 1.08), (0.3, 1), (0.34, 0.9), (0.42, 1), (0.64, 0.94), (0.76, 1)])
            p.happyL = t > 0.15 && t < 1.05; p.happyR = p.happyL
        case .nod:
            p.y = lerp(t, [(0, 0), (0.15, 3), (0.3, 0), (0.45, 3), (0.6, 0)])
            p.tilt = lerp(t, [(0, 0), (0.15, 2), (0.3, 0), (0.45, 2), (0.6, 0)])
            p.gazeX = 0.4; p.gazeY = 0.6
            p.openL = min(blink, 0.8); p.openR = p.openL
        case .stretch:
            let open = lerp(t, [(0, 1), (0.2, 0), (1.4, 0), (1.6, 1)])
            p.openL = min(blink, open); p.openR = p.openL
            p.scaleY = lerp(t, [(0, 1), (0.3, 0.9), (0.8, 1.16), (1.3, 1.16), (1.6, 0.96), (1.9, 1)])
            p.scaleX = lerp(t, [(0, 1), (0.3, 1.06), (0.8, 0.93), (1.3, 0.93), (1.6, 1.03), (1.9, 1)])
            p.tilt = t > 1.3 && t < 1.65 ? 3 * sin((t - 1.3) * .pi * 2 * 4.3) : 0
        case .doze:
            let open = lerp(t, [(0, 1), (0.6, 0.5), (1.4, 0.5), (1.8, 0.12), (2.3, 0.12), (2.4, 1)])
            p.openL = min(blink, open); p.openR = p.openL
            p.big = lerp(t, [(0, 0), (2.3, 0), (2.4, 1), (2.65, 0)])
            p.y = lerp(t, [(0, 0), (1.8, 3), (2.3, 3), (2.4, -4), (2.8, 0)])
            p.scaleY = lerp(t, [(0, 1), (1.8, 0.97), (2.3, 0.97), (2.4, 1.06), (2.8, 1)])
            p.tilt = lerp(t, [(0, 0), (1.8, -3), (2.3, -3), (2.4, 0)])
            p.gazeX = t < 2.3 ? 0.3 : 1; p.gazeY = t < 2.3 ? 0.6 : 0
        case .peekaboo:
            p.y = lerp(t, [(0, 0), (0.25, -4), (0.5, 110), (0.95, 110), (1.25, -8), (1.45, 0)])
            p.scaleY = lerp(t, [(0, 1), (0.25, 1.05), (0.5, 0.9), (1.25, 1.08), (1.45, 1)])
            let open = lerp(t, [(0, 1), (0.3, 0), (1.0, 0), (1.15, 1)])
            p.openL = min(blink, open); p.openR = p.openL
            p.big = lerp(t, [(1.0, 0), (1.2, 1), (1.45, 0)])
            p.happyL = t > 1.45; p.happyR = p.happyL
        case .listening:
            p.gazeX = 0.25; p.gazeY = 1
            p.y = 1.2 * sin(t * .pi * 2 / 0.9)
            let l = t.truncatingRemainder(dividingBy: 2.4)
            p.tilt = lerp(l, [(0, 0), (1.8, 0), (2.0, 3), (2.2, 0), (2.4, 0)])
            p.scaleY = 1 + 0.012 * breathe
            p.openL = min(blink, 0.9); p.openR = p.openL
        }
        return p
    }

    /// Static pose for Reduce Motion: the state's settled expression with no breathing or sway.
    public static func restingPose(state: BlotState) -> BlotPose {
        var resting = pose(state: state, elapsed: restingTime)
        resting.x = 0; resting.y = 0; resting.tilt = 0
        resting.scaleX = 1; resting.scaleY = 1
        if state == .peek || state == .peekaboo { resting.openL = 1; resting.openR = 1 }
        return resting
    }

    private static func lerp(_ time: Double, _ frames: [(Double, Double)]) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        if time <= first.0 { return first.1 }
        for index in 1..<frames.count where time <= frames[index].0 {
            let previous = frames[index - 1], next = frames[index]
            let progress = (time - previous.0) / (next.0 - previous.0)
            let eased = progress * progress * (3 - 2 * progress)
            return previous.1 + (next.1 - previous.1) * eased
        }
        return last.1
    }
}
