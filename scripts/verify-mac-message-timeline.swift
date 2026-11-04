import Foundation

@main @MainActor
enum VerifyMacMessageTimeline {
    private static var checks = 0
    private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: " + message) }
        checks += 1
    }

    static func main() {
        let history = MacDemoMessage(text: "History")
        let outgoing = MacDemoMessage(isUser: true, text: "First send")
        let reply = MacDemoMessage(text: "First reply")
        let secondOutgoing = MacDemoMessage(isUser: true, text: "Second send")
        let secondReply = MacDemoMessage(text: "Second reply")
        let restored = MacTeamMessageTimeline(messages: [history, outgoing, reply])
        check(restored.visibleIDs == Set([history.id, outgoing.id, reply.id]), "restored history is ready for the first layout")
        check(restored.entranceIDs.isEmpty && restored.lastRevealedID == nil, "restored history does not animate or scroll")
        check(!restored.synchronize([history, outgoing, reply], immediate: false) && !restored.revealNext(),
              "first appearance does not restage restored history")
        let timeline = MacTeamMessageTimeline()
        check(!timeline.synchronize([history], immediate: false), "opening history is not a send")
        check(timeline.visibleIDs == [history.id] && timeline.entranceIDs.isEmpty, "history appears without entrance")
        check(timeline.lastRevealedID == nil, "opening history does not animate a scroll")
        let firstBatch = [history, outgoing, reply]
        check(timeline.synchronize(firstBatch, immediate: false), "new outgoing is detected")
        check(timeline.visibleIDs.contains(outgoing.id) && !timeline.visibleIDs.contains(reply.id), "send precedes reply")
        timeline.didAppear(outgoing.id)
        check(!timeline.entranceIDs.contains(outgoing.id), "scrolled-away messages will not repeat their entrance")
        check(!timeline.synchronize(firstBatch, immediate: false), "cancellation followed by resynchronization is not another send")
        check(timeline.revealNext() && timeline.visibleIDs.contains(reply.id), "pending reply survives cancellation")
        check(!timeline.revealNext(), "no duplicate replies")

        let burst = MacTeamMessageTimeline()
        burst.synchronize([history], immediate: false)
        burst.synchronize(firstBatch, immediate: false)
        let bothBatches = firstBatch + [secondOutgoing, secondReply]
        check(burst.synchronize(bothBatches, immediate: false), "rapid second send is detected")
        check(burst.visibleIDs.contains(reply.id) && burst.visibleIDs.contains(secondOutgoing.id), "rapid sends retain preceding replies")
        check(!burst.visibleIDs.contains(secondReply.id), "second reply awaits its own entrance")
        check(burst.revealNext() && burst.lastRevealedID == secondReply.id, "burst ends at the latest reply")
        check(!burst.revealNext(), "rapid sends do not duplicate pending items")
        burst.synchronize([history], immediate: false)
        check(burst.visibleIDs == [history.id] && burst.entranceIDs.isEmpty, "removed IDs are discarded")

        let reduced = MacTeamMessageTimeline()
        reduced.synchronize([history], immediate: false)
        check(reduced.synchronize(firstBatch, immediate: true), "reduced motion still recognizes outgoing sends")
        check(reduced.visibleIDs == Set(firstBatch.map(\.id)) && reduced.entranceIDs.isEmpty, "reduced motion immediately exposes every message")
        check(!reduced.revealNext(), "reduced motion leaves no delayed replies")

        let readingHistory = MacTeamMessageTimeline()
        readingHistory.synchronize([history], immediate: false)
        readingHistory.synchronize([history, reply], immediate: false, followingLatest: false)
        check(readingHistory.visibleIDs.contains(reply.id) && readingHistory.entranceIDs.isEmpty,
              "receiving while reading history does not replay an entrance later")
        check(readingHistory.synchronize(firstBatch, immediate: false, followingLatest: false), "sending from history resumes following the conversation")

        let reopened = MacTeamMessageTimeline()
        reopened.synchronize(bothBatches, immediate: false)
        check(reopened.visibleIDs.count == bothBatches.count && !reopened.revealNext(), "reopening shows all persisted messages at once")
        check(reopened.entranceIDs.isEmpty, "reopening does not replay previous animations")
        let liveHistory = MacTeamMessageTimeline.Item(id: UUID().uuidString, isUser: false)
        let liveSend = MacTeamMessageTimeline.Item(id: UUID().uuidString, isUser: true)
        let liveReply = MacTeamMessageTimeline.Item(id: UUID().uuidString, isUser: false)
        let live = MacTeamMessageTimeline(items: [liveHistory])
        check(live.visibleIDs == [liveHistory.id] && live.entranceIDs.isEmpty, "live restored history never replays")
        check(live.synchronize(items: [liveHistory, liveSend, liveReply], immediate: false), "live outgoing message uses the same timeline")
        check(live.entranceIDs.contains(liveSend.id) && !live.visibleIDs.contains(liveReply.id), "live send precedes assistant entrance")
        live.didAppear(liveSend.id)
        check(!live.synchronize(items: [liveHistory, liveSend, liveReply], immediate: false), "streaming the same live IDs is not a second send")
        check(live.revealNext() && live.entranceIDs.contains(liveReply.id), "live assistant entrance survives updates")
        live.didAppear(liveReply.id)
        live.synchronize(items: [liveHistory, liveSend, liveReply], immediate: false)
        check(live.entranceIDs.isEmpty && !live.revealNext(), "live streaming never repeats its entrance")
        live.synchronize(items: [liveHistory], immediate: false)
        check(live.visibleIDs == [liveHistory.id], "live deletion removes stale presentation IDs")
        live.synchronize(items: [liveHistory, liveSend, liveReply], immediate: true)
        check(live.visibleIDs.count == 3 && live.entranceIDs.isEmpty, "live reduced motion exposes every message immediately")
        print("Passed \(checks) message timeline checks")
    }
}
