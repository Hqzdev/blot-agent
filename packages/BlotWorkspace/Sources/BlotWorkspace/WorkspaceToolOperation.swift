import Foundation

/// A bounded execution instruction; tool permissions and arguments remain independently validated.
public struct WorkspaceToolOperation: Decodable, Equatable, Sendable {
    public let toolID: String
    public let instruction: String
    public init(toolID: String, instruction: String) { self.toolID = toolID; self.instruction = instruction }
}
