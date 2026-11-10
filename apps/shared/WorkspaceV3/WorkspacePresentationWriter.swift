import Foundation

/// Coalesces UI edits before encoding their immutable snapshot away from the main actor.
@MainActor
final class WorkspacePresentationWriter {
    private var pending: Task<Void, Never>?
    private var saved: Data?
    private var revision = UUID()
    private var lastFailure: (any Error)?

    func schedule(_ state: WorkspacePresentationState, immediately: Bool,
                  save: @escaping @MainActor (Data) async throws -> Void) {
        pending?.cancel()
        let revision = UUID()
        self.revision = revision; lastFailure = nil
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
                if self.revision == revision { saved = data }
            } catch is CancellationError { }
            catch { if self?.revision == revision { self?.lastFailure = error } }
        }
    }

    func flush() async { await pending?.value }
    func flushReportingFailure() async throws {
        while true {
            let expected = revision
            await pending?.value
            if revision == expected { break }
        }
        if let lastFailure { throw lastFailure }
    }
    func reset() { pending?.cancel(); pending = nil; saved = nil; lastFailure = nil; revision = UUID() }
}
