import Foundation

/// UTF-8 bytes are a conservative token estimate until a provider tokenizer is available.
/// The 250k ceiling never overrides a smaller model window or a per-run budget.
public struct WorkspaceContextLimits: Sendable {
    public static let compactionTokenLimit = 250_000
    public let contextWindowTokens: Int
    public init(contextWindowTokens: Int = 32_768) {
        self.contextWindowTokens = max(1, contextWindowTokens)
    }
    func trigger(maximumCharacters: Int, outputTokens: Int, budgetTokens: Int) -> Int {
        let requestCapacity = max(0, min(contextWindowTokens, budgetTokens) - outputTokens - 4096)
        return min(Self.compactionTokenLimit, maximumCharacters, max(1024, requestCapacity / 2))
    }
    func requestBudget(_ budgetTokens: Int) -> Int { min(contextWindowTokens, budgetTokens) }
}
