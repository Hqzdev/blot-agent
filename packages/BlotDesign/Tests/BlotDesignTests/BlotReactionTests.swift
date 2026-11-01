import Foundation
import Testing
@testable import BlotDesign

/// Manual clock for reaction timing.
private final class Clock {
    var date = Date(timeIntervalSinceReferenceDate: 1_000)
    func advance(_ seconds: Double) { date.addTimeInterval(seconds) }
}

@Suite struct BlotReactionTests {
    @Test func failureIsNotHiddenByTyping() {
        let clock = Clock()
        let reactions = BlotReactionController(now: { clock.date })
        #expect(reactions.receive(.sendFailed))
        #expect(!reactions.receive(.typing))
        #expect(reactions.state(over: .idle) == .error)
    }

    @Test func failureReplacesSent() {
        let clock = Clock()
        let reactions = BlotReactionController(now: { clock.date })
        reactions.receive(.sent)
        clock.advance(0.2)
        #expect(reactions.receive(.sendFailed))
        #expect(reactions.current == .sendFailed)
    }

    @Test func sentReplacesTypingAndReplays() {
        let clock = Clock()
        let reactions = BlotReactionController(now: { clock.date })
        reactions.receive(.typing)
        let before = reactions.generation
        reactions.receive(.sent)
        #expect(reactions.current == .sent)
        #expect(reactions.generation == before + 1)
        reactions.receive(.sent)
        #expect(reactions.generation == before + 2)
    }

    @Test func typingExtendsWithoutReplaying() {
        let clock = Clock()
        let reactions = BlotReactionController(now: { clock.date })
        reactions.receive(.typing)
        let generation = reactions.generation
        clock.advance(1.0)
        reactions.receive(.typing)
        clock.advance(1.0)
        reactions.expire()
        #expect(reactions.current == .typing)
        #expect(reactions.generation == generation)
    }

    @Test func reactionsExpire() {
        let clock = Clock()
        let reactions = BlotReactionController(now: { clock.date })
        reactions.receive(.sendFailed)
        clock.advance(BlotComposerEvent.sendFailed.holdDuration + 0.01)
        reactions.expire()
        #expect(reactions.current == nil)
        #expect(reactions.state(over: .idle) == .idle)
        // After expiry a lower-priority event is accepted again.
        #expect(reactions.receive(.typing))
    }

    @Test func cancelClearsImmediately() {
        let clock = Clock()
        let reactions = BlotReactionController(now: { clock.date })
        reactions.receive(.sendFailed)
        reactions.cancel()
        #expect(reactions.current == nil)
        #expect(reactions.remaining == nil)
        #expect(reactions.receive(.typing))
    }

    @Test(arguments: [BlotState.waiting, .blocked, .error])
    func attentionStatesWin(_ base: BlotState) {
        let reactions = BlotReactionController()
        reactions.receive(.sent)
        #expect(reactions.state(over: base) == base)
    }
}

@Suite struct BlotDirectorTests {
    @Test func failureInterruptsAndTypingWaitsForIt() {
        let clock = Clock()
        let director = BlotDirector(now: { clock.date }, random: { $0.lowerBound })
        director.tick(.lively)
        director.stimulate(.failure)
        director.tick(.lively)
        #expect(director.act == .error)
        director.stimulate(.typing)
        director.tick(.lively)
        #expect(director.act == .error)
        clock.advance(1)
        director.tick(.lively)
        #expect(director.act == .listening)
    }

    @Test func sleepsAfterFiveIdleMinutesAndWakesOnTyping() {
        let clock = Clock()
        let director = BlotDirector(now: { clock.date }, random: { $0.lowerBound })
        director.tick(.lively)
        clock.advance(301)
        director.tick(.lively)
        if director.act != .sleep { clock.advance(7); director.tick(.lively) }
        #expect(director.act == .sleep)
        director.stimulate(.typing)
        director.tick(.lively)
        #expect(director.act == .wakeUp)
    }

    @Test func noPointerMeansNoPointerReactions() {
        let clock = Clock()
        let director = BlotDirector(now: { clock.date }, random: { $0.lowerBound })
        director.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        director.pointer = { nil }
        for _ in 0..<20 { clock.advance(0.1); director.tick(.lively) }
        #expect(director.act != .wink)
    }
}

@Suite struct BlotMotionTests {
    @Test(arguments: BlotState.allCases)
    func restingPoseIsStill(_ state: BlotState) {
        let pose = BlotMotion.restingPose(state: state)
        #expect(pose.x == 0 && pose.y == 0 && pose.tilt == 0)
        #expect(pose.scaleX == 1 && pose.scaleY == 1)
    }

    @Test func errorRestsSad() {
        #expect(BlotMotion.restingPose(state: .error).sad)
    }

    @Test func everyRoleHasAccessoryEntry() {
        for role in BlotRole.allCases { #expect(BlotGeometry.accessories[role] != nil) }
    }
}
