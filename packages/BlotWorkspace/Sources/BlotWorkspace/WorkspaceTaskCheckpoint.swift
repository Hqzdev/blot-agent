import BlotDomain
import Foundation

public enum WorkspaceTaskExecutionError: Error, Equatable, Sendable {
    case uncertainToolResult, invalidCheckpoint, notRunnable
}

/// Reconstructs only this task's durable model context. Missing tool results are never replayed.
public struct WorkspaceTaskCheckpoint: Sendable {
    public let messages: [ChatModelMessage]
    public let nextStepIndex: Int
    public let hasFinalResponse: Bool
    public let hasFailedResults: Bool
    private let results: [String: ChatJSON]

    public init(taskID: UUID, projection: WorkspaceProjection) throws {
        let steps = projection.modelSteps.filter { $0.taskId == taskID }.sorted {
            $0.stepIndex == $1.stepIndex ? $0.metadata.createdAt < $1.metadata.createdAt : $0.stepIndex < $1.stepIndex
        }
        var recorded: [String: ChatJSON] = [:]
        var latestResults: [String: ChatJSON] = [:]
        var byStep: [UUID: [String: ChatJSON]] = [:]
        for step in steps {
            guard let raw = step.toolCallsJSON else { continue }
            guard let calls = try? JSONDecoder().decode([ChatToolCall].self, from: Data(raw.utf8)),
                  let values = try? JSONDecoder().decode([String: ChatJSON].self, from: Data((step.toolResultsJSON ?? "{}").utf8)) else {
                throw WorkspaceTaskExecutionError.uncertainToolResult
            }
            for call in calls {
                let saved = values[call.id]
                let pendingProcess = call.name == "process_run" && saved?.mcpFields["state"] == .string("running")
                let result = saved == nil || saved.map(Self.isUnknown) == true || pendingProcess
                    ? Self.reconciledResult(call, step: step, projection: projection) : saved
                guard let result, !Self.isUnknown(result) else { throw WorkspaceTaskExecutionError.uncertainToolResult }
                byStep[step.metadata.id, default: [:]][call.id] = result
                let key = try Self.key(call)
                latestResults[key] = result
                recorded[key] = WorkspaceGroupExecutionEvidence.containsFailure(result) ? nil : result
            }
        }
        results = recorded
        hasFailedResults = latestResults.values.contains(where: WorkspaceGroupExecutionEvidence.containsFailure)
        guard let last = steps.last else {
            messages = []; nextStepIndex = 0; hasFinalResponse = false; return
        }
        guard let request = try? JSONDecoder().decode(ChatModelRequest.self, from: Data(last.requestJSON.utf8)) else {
            throw WorkspaceTaskExecutionError.invalidCheckpoint
        }
        nextStepIndex = last.stepIndex + 1
        var context = request.messages
        if let raw = last.toolCallsJSON {
            let calls = try JSONDecoder().decode([ChatToolCall].self, from: Data(raw.utf8))
            context.append(.init(role: "assistant", content: "", toolCalls: calls))
            let values = byStep[last.metadata.id] ?? [:]
            for call in calls {
                guard let result = values[call.id] else { throw WorkspaceTaskExecutionError.uncertainToolResult }
                context.append(.init(role: "tool", content: String(decoding: try JSONEncoder().encode(result), as: UTF8.self),
                    toolCallID: call.id, name: call.name))
            }
        }
        messages = context
        hasFinalResponse = last.state == .completed && last.toolCallsJSON == nil && projection.messages.contains {
            $0.metadata.id == last.responseMessageId && $0.delivery == .completed && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    public func recordedResult(for call: ChatToolCall) throws -> ChatJSON? { results[try Self.key(call)] }
    static func reconciledResult(_ call: ChatToolCall, step: BlotV3.ModelStep, projection: WorkspaceProjection) -> ChatJSON? {
        guard let workspaceID = step.metadata.workspaceId else { return nil }
        let actionID = WorkspaceToolCallIdentity.actionID(workspaceID: workspaceID, sourceID: step.sourceMessageId, callID: call.id)
        guard let action = projection.actions.first(where: { $0.metadata.id == actionID && $0.execution.taskId == step.taskId && $0.toolId == call.name }),
              let arguments = try? JSONDecoder().decode(ChatJSON.self, from: Data(action.parameters.utf8)), arguments == call.arguments else { return nil }
        // begin() records the invocation atomically before an external operation can start.
        guard let invocation = projection.invocations.first(where: { $0.preparedActionId == actionID }) else {
            guard [.waiting_approval, .approved, .denied, .expired].contains(action.state) else { return nil }
            return .object(["state": .string("failed"), "error": .string("The prepared action did not start. Any new attempt must use the normal permission flow.")])
        }
        guard [.succeeded, .failed].contains(invocation.state) else { return nil }
        if invocation.state == .failed { return .object(["state": .string("failed"), "error": .string("The action was confirmed as not completed.")]) }
        guard let raw = invocation.result else { return nil }
        return try? JSONDecoder().decode(ChatJSON.self, from: Data(raw.utf8))
    }
    private static func key(_ call: ChatToolCall) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return call.name + ":" + String(decoding: try encoder.encode(call.arguments), as: UTF8.self)
    }
    private static func isUnknown(_ value: ChatJSON) -> Bool {
        switch value {
        case .object(let fields):
            if case .string(let state) = fields["state"], ["unknown", "waiting_approval"].contains(state) { return true }
            return fields.values.contains(where: isUnknown)
        case .array(let values): return values.contains(where: isUnknown)
        default: return false
        }
    }
}
