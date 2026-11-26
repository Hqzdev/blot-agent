import Foundation

/// Reloads connection metadata between model turns, so newly authorized MCP tools
/// are usable in the same conversation. Implementations still authorize every call.
public final class WorkspaceRefreshingToolProvider: WorkspaceToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var current: any WorkspaceToolExecuting
    private let reload: @Sendable () async throws -> any WorkspaceToolExecuting
    public init(initial: any WorkspaceToolExecuting, reload: @escaping @Sendable () async throws -> any WorkspaceToolExecuting) {
        current = initial; self.reload = reload
    }
    private var provider: any WorkspaceToolExecuting { lock.withLock { current } }
    public var definitions: [ChatToolDefinition] { provider.definitions }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        let next = try await reload()
        lock.withLock { current = next }
        return try await next.availableDefinitions(context: context)
    }
    public func validate(_ call: ChatToolCall, definition: ChatToolDefinition) throws { try provider.validate(call, definition: definition) }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        try await provider.execute(call, context: context)
    }
}
