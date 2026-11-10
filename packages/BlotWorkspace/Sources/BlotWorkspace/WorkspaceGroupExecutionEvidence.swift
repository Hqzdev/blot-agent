import BlotDomain
import Foundation

/// A finished reply is not proof that its requested tool operations succeeded.
public struct WorkspaceGroupExecutionEvidence: Sendable {
    public let text: String
    public let hasFailures: Bool
    public let successfulTools: Set<String>
    public init(steps: [BlotV3.ModelStep]) {
        var lines: [String] = [], failed = false, succeeded: Set<String> = []
        for step in steps {
            if [.interrupted, .canceled].contains(step.state) { failed = true }
            guard let rawCalls = step.toolCallsJSON else { continue }
            guard let calls = try? JSONDecoder().decode([ChatToolCall].self, from: Data(rawCalls.utf8)),
                  let rawResults = step.toolResultsJSON,
                  let results = try? JSONDecoder().decode([String: ChatJSON].self, from: Data(rawResults.utf8)) else { failed = true; continue }
            lines.append("Calls: \(rawCalls)\nResults: \(rawResults)")
            for call in calls {
                guard let result = results[call.id], !Self.containsFailure(result) else { failed = true; continue }
                succeeded.insert(call.name)
            }
        }
        text = lines.joined(separator: "\n"); hasFailures = failed; successfulTools = succeeded
    }
    public static func containsFailure(_ value: ChatJSON) -> Bool {
        switch value {
        case .object(let fields):
            if fields["error"] != nil && fields["error"] != .null { return true }
            if case .string(let state) = fields["state"], ["failed", "unknown", "canceled", "waiting_approval"].contains(state) { return true }
            return fields.values.contains(where: containsFailure)
        case .array(let values): return values.contains(where: containsFailure)
        default: return false
        }
    }
}
