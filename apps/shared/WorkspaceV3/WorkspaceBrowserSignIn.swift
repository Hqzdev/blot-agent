import BlotDesign
import Observation

@MainActor @Observable
final class WorkspaceBrowserSignIn {
    private(set) var isActive = false
    @ObservationIgnored private var task: _Concurrency.Task<Void, Never>?

    func start(_ operation: @escaping @MainActor () async -> Void) {
        guard !isActive else { return }
        isActive = true
        task = _Concurrency.Task {
            defer { isActive = false; task = nil }
            #if os(iOS)
            // Let the split finish before the system browser covers the welcome screen.
            do { try await _Concurrency.Task.sleep(for: .seconds(BlotInterfaceMotion.Duration.standard)) }
            catch { return }
            #endif
            guard !_Concurrency.Task.isCancelled else { return }
            await operation()
        }
    }

    func cancel() { task?.cancel() }
}
