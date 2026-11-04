import Foundation

/// Shared by all chat and task runtimes in one installation. Waiting is cancellable.
public actor WorkspaceExecutorPool {
    private var active = 0
    private let limit: Int
    public init(limit: Int = 4) { self.limit = min(4, max(1, limit)) }
    public func acquire() async throws {
        while active >= limit {
            try _Concurrency.Task.checkCancellation()
            try await _Concurrency.Task.sleep(for: .milliseconds(25))
        }
        try _Concurrency.Task.checkCancellation()
        active += 1
    }
    public func release() { precondition(active > 0); active -= 1 }
}
