//
//  Motion.swift
//  Blot
//
//  One motion system for the Mac and iPhone apps. Every animation uses these tokens so timing
//  stays consistent. Animations are springs without bounce: they start on the same frame as the
//  input, settle with a natural ease-out and retarget from the current velocity when the user
//  repeats an action mid-flight. Movement is limited to short shifts and fades.
//

import BlotDesign
import SwiftUI

typealias KMotion = BlotInterfaceMotion

extension AnyTransition {
    /// Fade with a short shift that starts on the side of `edge` and ends in place.
    static func kShift(from edge: Edge) -> AnyTransition {
        let distance = KMotion.shift
        let offset: CGSize = switch edge {
        case .top: CGSize(width: 0, height: -distance)
        case .bottom: CGSize(width: 0, height: distance)
        case .leading: CGSize(width: -distance, height: 0)
        case .trailing: CGSize(width: distance, height: 0)
        }
        return .opacity.combined(with: .offset(offset))
    }

    /// Content appearing in place: rises into position while fading in.
    static var kAppear: AnyTransition { kShift(from: .bottom) }
    /// Banners and popovers attached to the top: settle downward.
    static var kNotice: AnyTransition { kShift(from: .top) }
    /// Side panels that enter from a window edge.
    static func kPanel(_ edge: Edge) -> AnyTransition { .move(edge: edge).combined(with: .opacity) }
}

// MARK: - Reduce Motion

extension View {
    /// Root of a window: publishes `blotReduceMotion` and, when it is on, removes every animation
    /// below so state changes apply instantly. `preference` is the in-app Reduce motion setting.
    func kMotionRoot(reduceMotion preference: Bool = false) -> some View {
        modifier(KMotionRoot(preference: preference))
    }

    /// Animates `value` changes with a motion token unless Reduce Motion is on.
    func kAnimation<V: Equatable>(_ animation: Animation = KMotion.standard, value: V) -> some View {
        modifier(KAnimationModifier(animation: animation, value: value))
    }
}

private struct KMotionRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var system
    let preference: Bool

    func body(content: Content) -> some View {
        let reduced = system || preference
        content
            .transaction { if reduced { $0.animation = nil; $0.disablesAnimations = true } }
            .environment(\.blotReduceMotion, reduced)
    }
}

private struct KAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.blotReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// Runs `body` inside `withAnimation` unless Reduce Motion is on.
@MainActor func withKAnimation<Result>(_ reduceMotion: Bool, _ animation: Animation? = nil,
                                       _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(reduceMotion ? nil : (animation ?? KMotion.standard), body)
}
