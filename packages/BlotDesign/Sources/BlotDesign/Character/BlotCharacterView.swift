//
//  BlotCharacterView.swift
//  BlotDesign
//
//  The animated character. It receives its state and events as parameters and knows nothing
//  about app state or the network. Platform adapters add input such as pointer tracking.
//  Animation stops while the view is off screen or the scene is inactive; with Reduce Motion
//  the character shows a still pose for its state.
//

import SwiftUI

public struct BlotCharacterView: View {
    private let role: BlotRole
    private let state: BlotState
    private let size: CGFloat
    private let replay: Int
    private let framing: BlotFraming
    private let behavior: BlotBehavior
    private let reduceMotion: Bool
    private let intro: Bool
    private let tappable: Bool
    private let stimulus: BlotStimulusEvent?
    private let followsPointer: Bool
    private let pointer: (@MainActor () -> CGPoint?)?
    private let label: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()
    @State private var blinkStarted: Date?
    @State private var finished = false
    @State private var introPlayed = false
    @State private var frame: CGRect = .zero
    @State private var director = BlotDirector()
    @State private var visible = false

    /// - Parameters:
    ///   - behavior: `.lively` for a hero character, `.subtle` for avatars, `.none` to play `state` only.
    ///   - reduceMotion: system or in-app setting; shows a still pose.
    ///   - stimulus: latest event for this character; a new `id` triggers a reaction.
    ///   - followsPointer: eyes follow `pointer` while resting.
    ///   - pointer: pointer location in the global coordinate space, if the platform has one.
    public init(role: BlotRole = .blot, state: BlotState = .idle, size: CGFloat = 40, replay: Int = 0,
                framing: BlotFraming = .stage, behavior: BlotBehavior = .subtle, reduceMotion: Bool = false,
                intro: Bool = false, tappable: Bool = false, stimulus: BlotStimulusEvent? = nil,
                followsPointer: Bool = false, pointer: (@MainActor () -> CGPoint?)? = nil, accessibilityLabel: String? = nil) {
        self.role = role
        self.state = state
        self.size = size
        self.replay = replay
        self.framing = framing
        self.behavior = reduceMotion ? .none : behavior
        self.reduceMotion = reduceMotion
        self.intro = intro
        self.tappable = tappable
        self.stimulus = stimulus
        self.followsPointer = followsPointer
        self.pointer = pointer
        self.label = accessibilityLabel ?? "Blot · \(state.title)"
    }

    private var active: Bool { scenePhase == .active && visible }
    /// The director takes over whenever the agent has nothing to say.
    private var ambient: Bool { state == .idle && behavior != .none }

    public var body: some View {
        Group {
            if reduceMotion {
                BlotDrawing(role: role, pose: BlotMotion.restingPose(state: state), framing: framing)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30,
                                        paused: !active || (!ambient && finished && !followsPointer))) { timeline in
                    let current = ambient ? director.act : state
                    let since = ambient ? director.actStart : started
                    let elapsed = max(0, timeline.date.timeIntervalSince(since))
                    let effective: BlotState = !ambient && state == .idle && elapsed > 300 ? .sleep : current
                    let pose = adjusted(
                        BlotMotion.pose(state: effective, elapsed: elapsed,
                                        blink: effective == .sleep ? 1 : blink(at: timeline.date),
                                        variant: ambient ? director.variant : 0),
                        state: effective)
                    BlotDrawing(role: role, pose: pose, framing: framing, elapsed: elapsed)
                }
            }
        }
        .frame(width: size, height: size)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { value in
            frame = value
            director.frame = value
        }
        .modifier(BlotTapReaction(enabled: tappable && ambient) { director.poke() })
        .onAppear {
            visible = true
            director.pointer = pointer
        }
        .onDisappear { visible = false }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
        .task(id: "\(state.rawValue)-\(replay)-\(reduceMotion)-\(active)") {
            guard active, !reduceMotion else { return }
            started = Date(); finished = false
            if let duration = state.duration {
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled { finished = true }
            }
        }
        .task(id: "\(ambient)-\(behavior)-\(active)") {
            guard ambient && active else { return }
            director.framing = framing
            director.pointer = pointer
            let playIntro = intro && !introPlayed
            introPlayed = true
            await director.run(behavior, intro: playIntro)
        }
        .task(id: "\(reduceMotion)-\(active)") {
            guard !reduceMotion && active else { blinkStarted = nil; return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(Double.random(in: 3...5))) } catch { return }
                blinkStarted = Date()
            }
        }
        .onChange(of: stimulus) { _, event in
            guard let event, active, ambient, behavior == .lively else { return }
            director.stimulate(event.kind)
        }
    }

    /// While resting, a nearby pointer pulls his gaze.
    private func adjusted(_ pose: BlotPose, state: BlotState) -> BlotPose {
        guard followsPointer, state == .idle || state == .planning, let point = pointer?() else { return pose }
        let eye = BlotDrawing.eyeCenter(in: frame, framing: framing)
        let dx = point.x - eye.x, dy = point.y - eye.y
        let distance = hypot(dx, dy)
        guard distance < 240 else { return pose }
        var copy = pose
        if distance < 8 { copy.gazeX = 0; copy.gazeY = 0 } else { copy.gazeX = dx / distance; copy.gazeY = dy / distance }
        return copy
    }

    private func blink(at date: Date) -> Double {
        guard let start = blinkStarted else { return 1 }
        let elapsed = date.timeIntervalSince(start)
        guard elapsed >= 0 && elapsed < 0.24 else { return 1 }
        return abs(elapsed - 0.12) / 0.12
    }
}

/// Adds a click or tap reaction only where the character is not part of another control.
private struct BlotTapReaction: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled { content.contentShape(Rectangle()).onTapGesture(perform: action) } else { content }
    }
}
