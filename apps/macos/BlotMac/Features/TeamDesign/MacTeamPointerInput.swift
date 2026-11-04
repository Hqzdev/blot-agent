import AppKit
import SwiftUI

enum MacTeamScrollInput {
    case begin, change(CGSize), end(cancelled: Bool)
}

/// Transparent geometry anchor. It never takes mouse hits or changes the text responder.
struct MacTeamPointerInput: NSViewRepresentable {
    var onSecondaryClick: (() -> Void)? = nil
    var onScroll: ((MacTeamScrollInput) -> Bool)? = nil
    var viewportInsets: EdgeInsets? = nil

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.onSecondaryClick = onSecondaryClick
        view.onScroll = onScroll
        view.viewportInsets = viewportInsets
        MacTeamPointerRouter.shared.register(view)
        return view
    }

    func updateNSView(_ view: Anchor, context: Context) {
        view.onSecondaryClick = onSecondaryClick
        view.onScroll = onScroll
        view.viewportInsets = viewportInsets
    }

    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        MacTeamPointerRouter.shared.unregister(view)
    }

    final class Anchor: NSView {
        var onSecondaryClick: (() -> Void)?
        var onScroll: ((MacTeamScrollInput) -> Bool)?
        var viewportInsets: EdgeInsets?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func contains(_ event: NSEvent) -> Bool {
            guard window === event.window, !isHiddenOrHasHiddenAncestor else { return false }
            let point = convert(event.locationInWindow, from: nil)
            return bounds.contains(point) && visibleRect.contains(point)
        }

        func containsInViewport(_ event: NSEvent) -> Bool {
            guard contains(event), let insets = viewportInsets else { return false }
            let region = CGRect(x: bounds.minX + insets.leading, y: bounds.minY + insets.top,
                                width: max(0, bounds.width - insets.leading - insets.trailing),
                                height: max(0, bounds.height - insets.top - insets.bottom))
            return region.contains(convert(event.locationInWindow, from: nil))
        }
    }
}

/// A single app-local monitor routes events only to visible, registered message regions.
@MainActor private final class MacTeamPointerRouter {
    static let shared = MacTeamPointerRouter()
    private final class Target {
        weak var view: MacTeamPointerInput.Anchor?
        init(_ view: MacTeamPointerInput.Anchor) { self.view = view }
    }
    private var targets: [Target] = []
    private var monitor: Any?
    private weak var scrolling: MacTeamPointerInput.Anchor?
    private var translation = CGSize.zero
    private var captured = false
    private var swallowingMomentum = false
    private var scrollSequenceActive = false

    func register(_ view: MacTeamPointerInput.Anchor) {
        targets.append(Target(view))
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown, .scrollWheel]) { [weak self] event in
                // Local monitors run synchronously inside NSApplication's main event dispatch.
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.route(event) == nil
                }
                return consumed ? nil : event
            }
        }
    }

    func unregister(_ view: MacTeamPointerInput.Anchor) {
        if scrolling === view {
            scrolling = nil
            translation = .zero
            captured = false
            swallowingMomentum = false
        }
        targets.removeAll { $0.view == nil || $0.view === view }
        if targets.isEmpty, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            swallowingMomentum = false
            scrollSequenceActive = false
        }
    }

    private func route(_ event: NSEvent) -> NSEvent? {
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            guard insideConversation(event) else { return event }
            guard let target = targets.reversed().compactMap(\.view).first(where: { $0.onSecondaryClick != nil && $0.contains(event) }) else { return event }
            target.onSecondaryClick?()
            return nil
        }
        guard event.type == .scrollWheel, event.hasPreciseScrollingDeltas else { return event }
        if !event.momentumPhase.isEmpty { return swallowingMomentum ? nil : event }
        guard !event.phase.isEmpty else { return event }
        if event.phase.contains(.began) || (!scrollSequenceActive && event.phase.contains(.changed)) {
            end(cancelled: true)
            scrollSequenceActive = true
            swallowingMomentum = false
            scrolling = insideConversation(event) ? targets.reversed().compactMap(\.view).first { $0.onScroll != nil && $0.contains(event) } : nil
            _ = scrolling?.onScroll?(.begin)
        }
        guard let scrolling, scrolling.window === event.window else {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { end(cancelled: true) }
            return event
        }
        // The requested gesture is fingers right -> bubble left, independent of natural scrolling.
        translation.width += MacTeamReplySwipeState.trackpadDelta(event.scrollingDeltaX, naturalScrolling: event.isDirectionInvertedFromDevice)
        translation.height += event.scrollingDeltaY
        captured = scrolling.onScroll?(.change(translation)) ?? false
        let consume = captured
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            end(cancelled: event.phase.contains(.cancelled))
        }
        return consume ? nil : event
    }

    private func insideConversation(_ event: NSEvent) -> Bool {
        targets.contains { $0.view?.containsInViewport(event) == true }
    }

    private func end(cancelled: Bool) {
        _ = scrolling?.onScroll?(.end(cancelled: cancelled))
        swallowingMomentum = captured && !cancelled
        scrolling = nil
        translation = .zero
        captured = false
        scrollSequenceActive = false
    }
}
