import Foundation

/// Direction locks once per gesture so vertical scrolling can never become a reply.
nonisolated struct MacTeamReplySwipeState {
    private enum Axis { case undecided, horizontal, other }
    static let threshold: CGFloat = 64
    private var axis: Axis = .undecided
    private(set) var offset: CGFloat = 0
    private(set) var armed = false
    var capturesGesture: Bool { axis == .horizontal }
    var progress: CGFloat { min(1, -offset / Self.threshold) }

    /// Physical fingers-right motion becomes negative bubble travel in either scroll preference.
    static func trackpadDelta(_ delta: CGFloat, naturalScrolling: Bool) -> CGFloat {
        delta * (naturalScrolling ? -1 : 1)
    }

    /// Returns true only when crossing the reply threshold from below.
    mutating func update(x: CGFloat, y: CGFloat) -> Bool {
        if axis == .undecided, max(abs(x), abs(y)) >= 8 {
            axis = x < 0 && abs(x) > abs(y) * 1.25 ? .horizontal : .other
        }
        guard capturesGesture else { return false }
        let distance = max(0, -x)
        let wasArmed = armed
        armed = distance >= Self.threshold
        offset = -min(112, min(distance, 88) + max(0, distance - 88) * 0.18)
        return armed && !wasArmed
    }

    mutating func finish(cancelled: Bool = false) -> Bool {
        let reply = capturesGesture && armed && !cancelled
        self = Self()
        return reply
    }
}
