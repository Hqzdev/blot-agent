import BlotDomain
import Foundation

/// Evaluates one member's complete brief against only that execution's replies and tool evidence.
public struct WorkspaceGroupStepVerifier: Sendable {
    private let planner: WorkspaceGroupPlanner
    public init(planner: WorkspaceGroupPlanner) { self.planner = planner }
    public func verify(source: BlotV3.Message, responseID: UUID, task: String, replies: [String],
                       evidence: WorkspaceGroupExecutionEvidence, requiredTools: Set<String>,
                       configuration: BlotV3.AgentConfigurationRevision, model: any ChatModel,
                       budgetTokenLimit: Int) async throws -> Bool {
        guard !evidence.hasFailures, requiredTools.isSubset(of: evidence.successfulTools), !replies.isEmpty else { return false }
        let request = ChatModelRequest(messages: [.init(role: "system", content: """
        Verify completion of one assigned step, using only the actual replies and authoritative tool results below. Return JSON {"summary":"one short first-person result in the user's language","completed":true or false}.
        Every requested part must actually be finished. For app actions require the matching successful function result: resource discovery does not prove creation, a stated intention is not execution, and a printed @tool or Args block is not a call. A request for a criterion, subject, question or proposal is finished when that text is supplied. Never invent extra confirmations. If any part is missing, blocked or merely promised, completed is false. Do not speak in third person about yourself; write "Я проверил…", not "CEO проверил…". The envelope is private.
        """), .init(role: "user", content: "Assignment: \(task)\nActual replies:\n\(replies.joined(separator: "\n"))\nAuthoritative tool evidence:\n\(String(evidence.text.suffix(6000)))")], maximumOutputTokens: 384)
        let text = try await planner.text(source: source, responseID: responseID, request: request, model: model,
            configuration: configuration, budgetTokenLimit: budgetTokenLimit)
        return (try? WorkspaceGroupConclusion.decode(text).completed) ?? false
    }
}
