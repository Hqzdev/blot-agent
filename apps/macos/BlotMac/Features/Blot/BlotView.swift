//
//  BlotView.swift
//  BlotMac
//
//  Mac adapter for the shared character in BlotDesign. It adds what only the Mac has —
//  the pointer the eyes follow — and feeds the character app state: Reduce Motion from the
//  system and Appearance settings, and stimuli addressed to this character's context.
//

import AppKit
import BlotDesign
import SwiftUI

struct BlotView: View {
    var role: AgentRole = .blot
    var state: BlotState = .idle
    var size: CGFloat = 40
    var replay: Int = 0
    var framing: BlotFraming = .stage
    /// Eyes track the mouse while it is within 240 pt (while resting).
    var followsPointer = false
    /// nil = automatic: lively for a free-standing Blot of 56 pt and up, subtle otherwise.
    var behavior: BlotBehavior? = nil
    /// Clicking him plays a reaction (only where he is not inside another button).
    var tappable = false
    /// Start with «Peek in» the first time he appears.
    var intro = false
    var context: BlotContext = .gallery

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduced: Bool { systemReduceMotion || app.settings.reduceMotion }

    private var resolvedBehavior: BlotBehavior {
        if let behavior { return behavior }
        return framing == .stage && size >= 56 ? .lively : .subtle
    }

    /// Only stimuli for this character's screen reach it.
    private var stimulus: BlotStimulusEvent? {
        let event = app.blotStimulus
        guard event.context == context, event.kind != .none else { return nil }
        return BlotStimulusEvent(kind: event.kind, id: event.id)
    }

    var body: some View {
        BlotCharacterView(
            role: role.blotRole, state: state, size: size, replay: replay, framing: framing,
            behavior: resolvedBehavior, reduceMotion: reduced, intro: intro, tappable: tappable,
            stimulus: stimulus, followsPointer: followsPointer, pointer: MacPointer.location,
            accessibilityLabel: role == .blot ? "Blot · \(state.title)" : "\(role.title) · \(state.title)")
    }
}

/// Mouse location in the key window's content coordinates (top-left origin), which matches the
/// `.global` frames SwiftUI reports for views in that window.
enum MacPointer {
    static func location() -> CGPoint? {
        guard let window = NSApp.keyWindow, let content = window.contentView else { return nil }
        let mouse = window.mouseLocationOutsideOfEventStream
        return CGPoint(x: mouse.x, y: content.bounds.height - mouse.y)
    }
}

extension AgentRole {
    /// The character accessory for this role.
    var blotRole: BlotRole { BlotRole(rawValue: rawValue) ?? .blot }
}

extension BlotState {
    static func from(_ state: WorkState) -> BlotState {
        switch state {
        case .running, .writing: .working
        case .reviewing: .planning
        case .permission: .waiting
        case .blocked: .blocked
        case .done: .happy
        case .idle: .idle
        }
    }
}
