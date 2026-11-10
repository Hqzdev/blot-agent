import BlotDomain
import Foundation

/// Explicit jumps cycle backwards; only a user's scroll resumes position-based selection.
struct PhonePinnedMessageNavigation {
    private(set) var selectedID: UUID?
    private(set) var highlightedID: UUID?
    private var tracksScrolling = true
    private var knownIDs: Set<UUID> = []
    private var messageIndices: [UUID: Int] = [:]

    func selected(in pins: [BlotV3.Message]) -> BlotV3.Message? {
        pins.first { $0.metadata.id == selectedID } ?? pins.last
    }

    mutating func reconcile(_ pins: [BlotV3.Message]) {
        let ids = Set(pins.map(\.metadata.id))
        if tracksScrolling, let added = pins.last(where: { !knownIDs.contains($0.metadata.id) }) {
            selectedID = added.metadata.id
        } else if !pins.contains(where: { $0.metadata.id == selectedID }) { selectedID = pins.last?.metadata.id }
        knownIDs = ids
    }

    mutating func selectPin(_ id: UUID, in pins: [BlotV3.Message]) {
        guard let index = pins.firstIndex(where: { $0.metadata.id == id }) else { return }
        selectedID = pins[index == 0 ? pins.count - 1 : index - 1].metadata.id
        reveal(id)
    }

    mutating func reveal(_ id: UUID) {
        tracksScrolling = false
        highlightedID = id
    }

    mutating func setMessageOrder(_ ids: [UUID]) {
        messageIndices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
    }

    mutating func beginScrolling() { tracksScrolling = true }

    mutating func update(visibleIDs: Set<UUID>, pins: [BlotV3.Message], atBottom: Bool) {
        guard tracksScrolling else { return }
        if atBottom { selectedID = pins.last?.metadata.id; return }
        guard let firstVisible = visibleIDs.compactMap({ messageIndices[$0] }).min() else { return }
        selectedID = pins.last(where: { (messageIndices[$0.metadata.id] ?? Int.max) <= firstVisible })?.metadata.id ?? pins.first?.metadata.id
    }

    mutating func clearHighlight(_ id: UUID) {
        if highlightedID == id { highlightedID = nil }
    }

    mutating func reset() { self = Self() }
}
