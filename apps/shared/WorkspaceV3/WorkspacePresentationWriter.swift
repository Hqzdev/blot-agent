import Foundation

/// Coalesces UI edits before encoding their immutable snapshot away from the main actor.
@MainActor
final class WorkspacePresentationWriter {
    private var pending: Task<Void, Never>?
    private var saved: Data?

    func schedule(_ state: WorkspacePresentationState, immediately: Bool,
                  save: @escaping @MainActor (Data) async throws -> Void) {
        pending?.cancel()
        pending = Task { [weak self] in
            do {
                if !immediately { try await Task.sleep(for: .milliseconds(250)) }
                let data = try await Task.detached(priority: .utility) {
                    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                    return try encoder.encode(state)
                }.value
                try Task.checkCancellation()
                guard let self, data != saved else { return }
                try await save(data)
                saved = data
            } catch is CancellationError { }
            catch { /* A later edit or lifecycle flush retries the latest state. */ }
        }
    }

    func flush() async { await pending?.value }
    func reset() { pending?.cancel(); pending = nil; saved = nil }
}
