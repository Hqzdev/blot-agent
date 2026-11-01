//
//  BlotReactions.swift
//  BlotDesign
//
//  Short reactions to the person's actions in a composer (typing, sending, a failed send).
//  A reaction only replaces one of lower or equal priority, expires on its own, and never
//  covers a state that needs attention (waiting, blocked, error from the agent).
//

import Foundation
import Observation

nonisolated public enum BlotComposerEvent: Sendable, Equatable {
    case typing, sent, sendFailed, succeeded

    /// Higher wins. A failure is never hidden by a later keystroke.
    public var priority: Int {
        switch self {
        case .typing: 1
        case .sent, .succeeded: 2
        case .sendFailed: 3
        }
    }

    public var state: BlotState {
        switch self {
        case .typing: .listening
        case .sent: .jump
        case .succeeded: .happy
        case .sendFailed: .error
        }
    }

    /// How long the reaction stays before the base state returns.
    public var holdDuration: Double {
        switch self {
        case .typing: 1.6
        default: (state.duration ?? 0.4) + 0.6
        }
    }

    public var stimulus: BlotStimulusKind {
        switch self {
        case .typing: .typing
        case .sent: .sent
        case .succeeded: .success
        case .sendFailed: .failure
        }
    }
}

@Observable
public final class BlotReactionController {
    public private(set) var current: BlotComposerEvent?
    /// Increments with every accepted reaction so views can replay a repeated one.
    public private(set) var generation = 0
    @ObservationIgnored private var expiresAt = Date.distantPast
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// Returns true when the event became the current reaction.
    @discardableResult
    public func receive(_ event: BlotComposerEvent) -> Bool {
        expire()
        if let current, current.priority > event.priority { return false }
        // Repeated keystrokes extend listening without replaying it.
        if current == .typing && event == .typing {
            expiresAt = now().addingTimeInterval(event.holdDuration)
            return true
        }
        current = event
        generation += 1
        expiresAt = now().addingTimeInterval(event.holdDuration)
        return true
    }

    /// Clears a reaction whose time is up. Call it on a timer or before reading `state(over:)`.
    public func expire() {
        if current != nil && now() >= expiresAt { current = nil }
    }

    /// Drops the current reaction, e.g. when the screen goes away or motion is reduced.
    public func cancel() {
        current = nil
        expiresAt = .distantPast
    }

    /// Seconds until the current reaction ends, or nil when there is none.
    public var remaining: Double? {
        guard current != nil else { return nil }
        return max(0, expiresAt.timeIntervalSince(now()))
    }

    /// The state to show: attention states from the agent win, then the reaction, then the base.
    public func state(over base: BlotState) -> BlotState {
        if base.isAttention { return base }
        return current?.state ?? base
    }
}
