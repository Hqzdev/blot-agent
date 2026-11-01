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

enum KMotion {
    /// Durations in seconds, also used by AppKit animations.
    enum Duration {
        static let press: Double = 0.12
        static let quick: Double = 0.15
        static let standard: Double = 0.22
        static let panel: Double = 0.28
    }

    /// Distance of the shift that accompanies a fade.
    static let shift: CGFloat = 6

    /// Press feedback.
    static let press = Animation.smooth(duration: Duration.press)
    /// Hover, focus, toggles and small content swaps.
    static let quick = Animation.smooth(duration: Duration.quick)
    /// State changes inside a view: tabs, disclosure, selection, list edits.
    static let standard = Animation.smooth(duration: Duration.standard)
    /// Screens, side panels, modals, banners and toasts.
    static let panel = Animation.smooth(duration: Duration.panel)
    /// Banners, toasts and inline notices that enter and leave.
    static let notice = Animation.smooth(duration: Duration.standard)
    /// Sidebar and side-panel show / hide.
    static let sidebar = Animation.smooth(duration: Duration.panel)
    /// Skeleton → content cross-fade.
    static let loading = Animation.easeOut(duration: 0.18)
}

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

private struct BlotReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the system or the in-app setting asks for reduced motion.
    var blotReduceMotion: Bool {
        get { self[BlotReduceMotionKey.self] }
        set { self[BlotReduceMotionKey.self] = newValue }
    }
}

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
@MainActor func withKAnimation<Result>(_ reduceMotion: Bool, _ animation: Animation = KMotion.standard,
                                       _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(reduceMotion ? nil : animation, body)
}
