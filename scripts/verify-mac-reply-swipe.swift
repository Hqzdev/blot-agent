import Foundation

@main enum VerifyReplySwipe {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ title: String) {
        guard value() else { fatalError(title) }
        checks += 1
    }

    static func main() {
        check(MacTeamReplySwipeState.trackpadDelta(80, naturalScrolling: true) == -80,
              "fingers right moves the bubble left with natural scrolling")
        check(MacTeamReplySwipeState.trackpadDelta(-80, naturalScrolling: false) == -80,
              "fingers right moves the bubble left with classic scrolling")
        check(MacTeamReplySwipeState.trackpadDelta(-80, naturalScrolling: true) > 0,
              "opposite finger movement does not arm a reply")
        var swipe = MacTeamReplySwipeState()
        check(!swipe.update(x: -4, y: 0) && swipe.offset == 0, "ignore pointer jitter")
        _ = swipe.update(x: -30, y: 2)
        check(swipe.capturesGesture && swipe.offset < 0, "leftward movement moves the bubble left")
        check(!swipe.finish(), "short swipe does not reply")
        check(swipe.offset == 0 && !swipe.capturesGesture, "release resets the gesture")

        check(swipe.update(x: -64, y: 1), "threshold arms reply and requests feedback")
        check(!swipe.update(x: -80, y: 1), "holding beyond threshold does not repeat feedback")
        check(swipe.armed && swipe.progress == 1, "reply indicator reaches completion")
        check(swipe.finish(), "release beyond threshold replies")
        check(!swipe.finish(), "one reply per gesture")

        _ = swipe.update(x: -90, y: 0)
        _ = swipe.update(x: -20, y: 0)
        check(!swipe.armed && !swipe.finish(), "returning below threshold cancels reply")
        _ = swipe.update(x: -80, y: 0)
        check(!swipe.finish(cancelled: true), "interrupted gesture never replies")

        _ = swipe.update(x: 80, y: 0)
        check(!swipe.capturesGesture && swipe.offset == 0, "rightward swipe remains untouched")
        _ = swipe.update(x: -100, y: 0)
        check(!swipe.capturesGesture && !swipe.finish(), "direction stays locked until release")

        _ = swipe.update(x: -3, y: 20)
        _ = swipe.update(x: -100, y: 30)
        check(!swipe.capturesGesture && !swipe.finish(), "vertical scrolling cannot turn into a reply")
        _ = swipe.update(x: -30, y: 28)
        check(!swipe.capturesGesture && !swipe.finish(), "ambiguous diagonal stays a normal scroll")

        _ = swipe.update(x: -10000, y: 0)
        check(swipe.offset >= -112 && swipe.offset < 0, "rubber band limits overshoot")
        _ = swipe.update(x: 10, y: 0)
        check(swipe.offset == 0 && !swipe.finish(), "returning past the origin never moves the bubble right")
        _ = swipe.update(x: -63.5, y: 0)
        check(!swipe.armed, "fractional scroll deltas below threshold do not arm")
        check(swipe.update(x: -64.5, y: 0), "accumulated fractional movement crosses the threshold")
        check(swipe.finish(), "fractional movement can complete a reply")
        print("Passed \(checks) reply swipe checks")
    }
}
