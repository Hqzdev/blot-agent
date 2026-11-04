import Foundation
import Observation

/// Stages persisted messages for presentation without delaying or changing stored data.
@MainActor @Observable
final class MacTeamMessageTimeline {
    struct Item: Equatable {
        let id: String
        let isUser: Bool
    }
    private(set) var visibleIDs: Set<String> = []
    private(set) var entranceIDs: Set<String> = []
    private(set) var lastRevealedID: String?
    @ObservationIgnored private var pending: [Item] = []
    @ObservationIgnored private var initialized = false

    init(messages: [MacDemoMessage]? = nil) {
        if let messages {
            visibleIDs = Set(messages.map(\.id))
            initialized = true
        }
    }

    init(items: [Item]) {
        visibleIDs = Set(items.map(\.id))
        initialized = true
    }

    /// Returns whether a new outgoing message should bring the conversation to the bottom.
    @discardableResult
    func synchronize(_ messages: [MacDemoMessage], immediate: Bool, followingLatest: Bool = true) -> Bool {
        synchronize(items: messages.map { Item(id: $0.id, isUser: $0.isUser) }, immediate: immediate, followingLatest: followingLatest)
    }

    @discardableResult
    func synchronize(items messages: [Item], immediate: Bool, followingLatest: Bool = true) -> Bool {
        let known = visibleIDs.union(pending.map(\.id))
        let hasOutgoing = initialized && messages.contains { $0.isUser && !known.contains($0.id) }
        let validIDs = Set(messages.map(\.id))
        if !initialized || immediate || (!followingLatest && !hasOutgoing) {
            visibleIDs = validIDs
            entranceIDs = []
            pending = []
            lastRevealedID = initialized ? messages.last?.id : nil
            initialized = true
            return hasOutgoing
        }
        visibleIDs.formIntersection(validIDs)
        entranceIDs.formIntersection(validIDs)
        pending = messages.filter { !visibleIDs.contains($0.id) }
        // A second send flushes preceding replies first, preserving the stored message order.
        if let lastOutgoing = pending.lastIndex(where: \.isUser) {
            for message in pending.prefix(through: lastOutgoing) { reveal(message) }
            pending.removeFirst(lastOutgoing + 1)
        }
        return hasOutgoing
    }

    @discardableResult
    func revealNext() -> Bool {
        guard !pending.isEmpty else { return false }
        reveal(pending.removeFirst())
        return true
    }

    func didAppear(_ id: String) { entranceIDs.remove(id) }

    private func reveal(_ message: Item) {
        visibleIDs.insert(message.id)
        entranceIDs.insert(message.id)
        lastRevealedID = message.id
    }
}
