import Foundation

public protocol WorkspaceScheduleClock: Sendable {
    func now() async -> Date
    func sleep(until date: Date) async throws
}

public struct WorkspaceSystemScheduleClock: WorkspaceScheduleClock {
    public init() {}
    public func now() async -> Date { Date() }
    public func sleep(until date: Date) async throws {
        try await _Concurrency.Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
    }
}
