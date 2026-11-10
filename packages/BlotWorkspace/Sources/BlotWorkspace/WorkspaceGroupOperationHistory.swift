import BlotDomain
import Foundation

/// A colleague handoff may revisit an assignment, but cannot repeat its completed writes.
public struct WorkspaceGroupOperationHistory: Sendable {
    private let results: [String: ChatJSON]
    private let unknown: Set<String>
    public init(sourceID: UUID, configurationID: UUID, projection: WorkspaceProjection) throws {
        var results: [String: ChatJSON] = [:], unknown: Set<String> = []
        for step in projection.modelSteps where step.sourceMessageId == sourceID && step.configurationId == configurationID {
            guard let raw = step.toolCallsJSON else { continue }
            let calls = try WorkspaceCoding.decode([ChatToolCall].self, from: Data(raw.utf8))
            let values = try WorkspaceCoding.decode([String: ChatJSON].self, from: Data((step.toolResultsJSON ?? "{}").utf8))
            for call in calls where Self.isWrite(call.name) {
                let key = try Self.key(call)
                var value = values[call.id]
                if value.map(Self.isUnknown) ?? true { value = WorkspaceTaskCheckpoint.reconciledResult(call, step: step, projection: projection) ?? value }
                guard let value else { unknown.insert(key); continue }
                if case .object(let fields) = value, case .string(let state) = fields["state"], ["unknown", "waiting_approval", "running"].contains(state) { unknown.insert(key) }
                else if !WorkspaceGroupExecutionEvidence.containsFailure(value) { results[key] = value }
            }
        }
        self.results = results; self.unknown = unknown
    }
    public func result(for call: ChatToolCall) throws -> ChatJSON? {
        let key = try Self.key(call)
        guard !unknown.contains(key) else { throw WorkspaceTaskExecutionError.uncertainToolResult }
        return results[key]
    }
    private static func isUnknown(_ value: ChatJSON) -> Bool {
        if case .object(let fields) = value, case .string(let state) = fields["state"] { return ["unknown", "waiting_approval", "running"].contains(state) }
        return false
    }
    private static func key(_ call: ChatToolCall) throws -> String { call.name + ":" + String(decoding: try WorkspaceCoding.encode(call.arguments), as: UTF8.self) }
    private static func isWrite(_ name: String) -> Bool {
        WorkspaceNativeCatalog.writes(name) || name.hasPrefix("mcp_") || name == "document_create" || name.hasPrefix("apple_") && ["create", "update", "delete", "send", "reply", "move", "run"].contains(String(name.split(separator: "_").last ?? ""))
    }
}
