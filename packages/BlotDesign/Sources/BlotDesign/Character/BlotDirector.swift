//
//  BlotDirector.swift
//  BlotDesign
//
//  Runs authored scenes between agent events. User reactions take priority over the
//  choreography. Small role avatars keep their own quiet, independent schedule.
//  Platform input (the pointer on Mac) arrives through `pointer`; the director never
//  touches AppKit, UIKit or app state.
//

import Foundation
import Observation

nonisolated public enum BlotBehavior: Sendable, Equatable {
    /// Plays exactly the state it is given.
    case none
    /// Small avatars: glances, nods, rare winks.
    case subtle
    /// Hero Blot (Home, empty states, composer): full personality and reactions.
    case lively
}

nonisolated public enum BlotStimulusKind: Sendable, Equatable {
    case none, typing, sent, success, failure
}

/// One stimulus delivered to a character. A new `id` replays the same kind.
nonisolated public struct BlotStimulusEvent: Sendable, Equatable {
    public var kind: BlotStimulusKind
    public var id: Int

    public init(kind: BlotStimulusKind, id: Int) {
        self.kind = kind
        self.id = id
    }
}

@Observable
public final class BlotDirector {
    public private(set) var act: BlotState = .idle
    public private(set) var actStart = Date()
    public private(set) var variant = 0.0

    /// The character's frame in the same coordinate space as `pointer`.
    @ObservationIgnored public var frame: CGRect = .zero
    @ObservationIgnored public var framing: BlotFraming = .stage
    /// Current pointer location, or nil when there is no pointer (iPhone) or it is unknown.
    @ObservationIgnored public var pointer: (@MainActor () -> CGPoint?)?

    @ObservationIgnored private var busyUntil = Date.distantPast
    @ObservationIgnored private var queue: [(BlotState, Double)] = []
    @ObservationIgnored private var lastInteraction = Date()
    @ObservationIgnored private var lastBig = Date.distantPast
    @ObservationIgnored private var lastBeat: BlotState = .idle
    @ObservationIgnored private var typingUntil = Date.distantPast
    @ObservationIgnored private var pointerNear = false
    @ObservationIgnored private var hoverStart: Date?
    @ObservationIgnored private var lastGreeting = Date.distantPast
    @ObservationIgnored private var lastGiggle = Date.distantPast
    @ObservationIgnored private var lastPointer: CGPoint?
    @ObservationIgnored private var choreography = BlotChoreography()

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let random: (ClosedRange<Double>) -> Double
    @ObservationIgnored private let wait: (Duration) async throws -> Void
    @ObservationIgnored private var nextBigAllowed = Date.distantPast

    public init(now: @escaping () -> Date = { Date() },
                random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) },
                wait: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.now = now; self.random = random; self.wait = wait
        actStart = now(); lastInteraction = now()
        nextBigAllowed = now()
    }

    /// Advances scheduling once. Tests provide a clock and repeat this without real waits.
    public func tick(_ behavior: BlotBehavior) {
        let protected = [.error, .wakeUp, .happy, .jump, .wink].contains(act)
        if behavior == .lively && queue.isEmpty && (!protected || now() >= busyUntil) { react() }
        guard now() >= busyUntil else { return }
        if !queue.isEmpty {
            let (beat, duration) = queue.removeFirst()
            play(beat, for: duration)
        } else {
            let (beat, duration) = choose(behavior)
            play(beat, for: duration)
        }
    }

    // MARK: Loop

    public func run(_ behavior: BlotBehavior, intro: Bool) async {
        let waking = act == .sleep || act == .doze || now().timeIntervalSince(lastInteraction) >= 300
        lastInteraction = now()
        queue.removeAll()
        if waking {
            queue = [(.wakeUp, 0.45), (.idle, 1.2)]
        } else if behavior == .lively && intro {
            queue = [(.peek, 0.75), (.happy, 1.1)]
        } else {
            // Desynchronise avatars that appear together.
            play(.idle, for: random(0.4...(behavior == .subtle ? 5 : 1.5)))
        }
        while !Task.isCancelled {
            tick(behavior)
            do { try await wait(.milliseconds(100)) } catch { return }
        }
    }

    // MARK: Stimuli

    public func stimulate(_ kind: BlotStimulusKind) {
        let wasAsleep = act == .sleep || act == .doze
        lastInteraction = now()
        switch kind {
        case .none:
            return
        case .typing:
            typingUntil = now().addingTimeInterval(1.6)
            if wasAsleep { interrupt([(.wakeUp, 0.45)]) }
            else if act == .error || act == .wakeUp {
                // Finish the important expression, then listen instead of playing its rest.
                queue.removeAll()
            } else if act != .listening && !act.isBig { interrupt([]) }
        case .sent:
            interrupt([(.jump, 0.8), (.happy, 1.2)])
        case .success:
            interrupt([(.happy, 1.1), (.wink, 0.8)])
        case .failure:
            interrupt([(.error, 0.9), (.idle, 1.2)])
        }
    }

    /// Clicked or tapped: wakes up if asleep, otherwise a little double hop.
    public func poke() {
        let wasAsleep = act == .sleep || act == .doze
        lastInteraction = now()
        interrupt(wasAsleep ? [(.wakeUp, 0.45), (.wink, 0.8)] : [(.bounce, 1.3), (.idle, 0.8)])
        lastBig = now()
    }

    private func interrupt(_ beats: [(BlotState, Double)]) {
        queue = beats
        busyUntil = .distantPast
    }

    private func play(_ beat: BlotState, for duration: Double) {
        act = beat
        actStart = now()
        variant = random(0...1)
        busyUntil = now().addingTimeInterval(duration)
        if beat != .idle { lastBeat = beat }
        if beat.isBig { lastBig = now(); nextBigAllowed = now().addingTimeInterval(6) }
    }

    // MARK: Reactions (lively only)

    private func react() {
        // Typing in the composer: watch it, then go back to normal life.
        if now() < typingUntil {
            let reacting = !queue.isEmpty || (act == .wakeUp && now() < busyUntil)
            if act != .listening && !reacting { play(.listening, for: 0.3) }
            if act == .listening { busyUntil = typingUntil }
            return
        }

        guard let pointer = pointerState() else { return }
        if pointer.moved && pointer.distance < 260 { lastInteraction = now() }

        let near = pointer.distance < 200
        if near && !pointerNear {
            if act == .sleep || act == .doze {
                interrupt([(.wakeUp, 0.45), (.happy, 1.1)])
            } else if now().timeIntervalSince(lastGreeting) > 12 && !act.isBig {
                interrupt([(.wink, 0.8)])
                lastGreeting = now()
            }
        }
        pointerNear = near

        if pointer.inside {
            if hoverStart == nil { hoverStart = now() }
            if let start = hoverStart, now().timeIntervalSince(start) > 1.2,
               now().timeIntervalSince(lastGiggle) > 6, act != .wiggle {
                interrupt([(.wiggle, 1.0), (.idle, 0.8)])
                lastGiggle = now()
                hoverStart = nil
            }
        } else {
            hoverStart = nil
        }
    }

    private func pointerState() -> (distance: Double, inside: Bool, moved: Bool)? {
        guard frame != .zero, let point = pointer?() else { return nil }
        let eye = BlotDrawing.eyeCenter(in: frame, framing: framing)
        let distance = hypot(point.x - eye.x, point.y - eye.y)
        let body = CGRect(x: frame.minX + frame.width * 0.15, y: frame.minY + frame.height * 0.32,
                          width: frame.width * 0.7, height: frame.height * 0.6)
        let moved = lastPointer.map { hypot($0.x - point.x, $0.y - point.y) > 1.5 } ?? false
        lastPointer = point
        return (distance, body.contains(point), moved)
    }

    // MARK: Choosing the next beat

    private func choose(_ behavior: BlotBehavior) -> (BlotState, Double) {
        if behavior == .subtle { return chooseSubtle() }
        if now().timeIntervalSince(lastInteraction) >= 300 { return (.sleep, 4) }
        let next = choreography.next
        // A user reaction may have happened just before the next scheduled hop.
        if next.state.isBig && now() < nextBigAllowed {
            return (lastBeat == .glance ? .curious : .glance, 1.6)
        }
        choreography.advance()
        if next.state != .idle && next.state == lastBeat { return choose(behavior) }
        let state = next.state == .peekaboo && framing != .stage ? BlotState.bounce : next.state
        return (state, next.duration)
    }

    private func chooseSubtle() -> (BlotState, Double) {
        let bigAllowed = now().timeIntervalSince(lastBig) > 25
        let table: [(BlotState, Double)] = [(.idle, 62), (.glance, 20), (.wink, 5), (.nod, 5), (.curious, 4), (.happy, bigAllowed ? 3 : 0)]
        let beat = weighted(table.filter { $0.1 > 0 && ($0.0 == .idle || $0.0 != lastBeat) })
        return (beat, beat == .idle ? random(3...8) : length(of: beat))
    }

    /// Beat length = motion length plus a short hold so the pose reads.
    private func length(of beat: BlotState) -> Double {
        switch beat {
        case .happy: 1.3
        case .wink: 0.9
        case .jump: 0.85
        case .planning: 2.4
        default: (beat.duration ?? 1.5) + 0.1
        }
    }

    private func weighted(_ table: [(BlotState, Double)]) -> BlotState {
        let total = table.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return .idle }
        var roll = min(total.nextDown, random(0...total))
        for (beat, weight) in table {
            if roll < weight { return beat }
            roll -= weight
        }
        return .idle
    }
}
