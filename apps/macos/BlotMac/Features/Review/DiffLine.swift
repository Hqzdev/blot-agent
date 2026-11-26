import Foundation

nonisolated enum DiffTone: Sendable { case context, added, removed, header }

nonisolated struct DiffLine: Identifiable, Sendable {
    let id: Int
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
    let tone: DiffTone
}
