import Foundation

/// Coordinates are viewport-relative and contain no page or input text.
public struct BrowserAgentPointer: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let x: Double
    public let y: Double
    public let operation: String
    public let activated: Bool
    public init(x: Double, y: Double, operation: String, activated: Bool = false) {
        self.x = min(1, max(0, x)); self.y = min(1, max(0, y)); self.operation = operation; self.activated = activated
    }
}
