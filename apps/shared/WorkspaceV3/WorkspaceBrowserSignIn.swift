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
            await operation()
        }
    }

    func cancel() { task?.cancel() }
}
