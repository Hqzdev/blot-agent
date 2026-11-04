import Foundation

/// Editing is local until Save; selection order also supplies a deterministic coordinator fallback.
struct WorkspaceGroupDraft {
    var title: String
    let creationCommandID = UUID()
    let expectedVersion: Int?
    private(set) var selectedIDs: [UUID]
    private(set) var coordinatorID: UUID?

    init(title: String = "", selectedIDs: [UUID] = [], coordinatorID: UUID? = nil, expectedVersion: Int? = nil) {
        self.title = title
        self.expectedVersion = expectedVersion
        var seen: Set<UUID> = []
        let unique = selectedIDs.filter { seen.insert($0).inserted }
        self.selectedIDs = unique
        self.coordinatorID = coordinatorID.flatMap { unique.contains($0) ? $0 : nil } ?? unique.first
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedIDs.isEmpty }
    var orderedAgentIDs: [UUID] {
        guard let coordinatorID else { return [] }
        return [coordinatorID] + selectedIDs.filter { $0 != coordinatorID }
    }

    mutating func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { remove(id) }
        else { selectedIDs.append(id); if coordinatorID == nil { coordinatorID = id } }
    }
    mutating func remove(_ id: UUID) {
        selectedIDs.removeAll { $0 == id }
        if coordinatorID == id { coordinatorID = selectedIDs.first }
    }
    mutating func selectAll(_ ids: [UUID]) {
        for id in ids where !selectedIDs.contains(id) { selectedIDs.append(id) }
        if coordinatorID == nil { coordinatorID = selectedIDs.first }
    }
    mutating func clear() { selectedIDs = []; coordinatorID = nil }
    mutating func coordinate(with id: UUID) { if selectedIDs.contains(id) { coordinatorID = id } }
    mutating func reconcile(availableIDs: Set<UUID>) {
        for id in selectedIDs where !availableIDs.contains(id) { remove(id) }
    }
}
