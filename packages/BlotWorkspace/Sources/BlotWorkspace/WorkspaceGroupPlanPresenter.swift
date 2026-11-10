import BlotDomain
import Foundation

/// First-person promises are display labels; the original execution briefs remain unchanged.
public struct WorkspaceGroupPlanPresenter: Sendable {
    private let planner: WorkspaceGroupPlanner
    public init(planner: WorkspaceGroupPlanner) { self.planner = planner }
    public func present(source: BlotV3.Message, responseID: UUID, decision: WorkspaceGroupDecision,
                        members: [BlotV3.AgentProfile], configuration: BlotV3.AgentConfigurationRevision,
                        model: any ChatModel, maximumOutputTokens: Int, budgetTokenLimit: Int) async throws -> WorkspaceGroupPlanProgress {
        let assignments = decision.assignments ?? []
        let roster = Dictionary(uniqueKeysWithValues: members.map { ($0.metadata.id, $0.name) })
        let request = ChatModelRequest(messages: [.init(role: "system", content: """
        Rewrite each assigned task as one short first-person future promise in the user's language, e.g. "Я проверю календари" or "I will create the draft". Each row is spoken by its own agent. Never use role labels, @names, imperatives addressed to yourself, or third-person narration. Preserve the actual requested action; do not claim it is done.
        Return JSON {"summary":"Work plan","assignments":[{"agentID":"unchanged UUID","task":"first-person promise"}]}. Keep exactly the same agent IDs and order. This is presentation only, not execution or permission.
        """), .init(role: "user", content: assignments.map { "\($0.agentID): \($0.task)" }.joined(separator: "\n"))], maximumOutputTokens: min(1536, maximumOutputTokens))
        var labels: [UUID: String] = [:]
        do {
            let text = try await planner.text(source: source, responseID: responseID, request: request, model: model,
                configuration: configuration, budgetTokenLimit: budgetTokenLimit)
            let plan = try WorkspaceGroupPlan.decode(text, memberIDs: Set(assignments.map(\.agentID)))
            if Set(plan.assignments.map(\.agentID)) == Set(assignments.map(\.agentID)) {
                for row in plan.assignments where Self.isFirstPerson(row.task) { labels[row.agentID] = row.task }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { /* Presentation failure must not replace an authorized execution brief. */ }
        let russian = source.content.range(of: #"[А-Яа-я]"#, options: .regularExpression) != nil
        return .init(summary: decision.summary ?? "", steps: assignments.map {
            .init(agentID: $0.agentID, name: roster[$0.agentID] ?? "", task: labels[$0.agentID]
                ?? (russian ? "Я выполню задачу: «\($0.task)»" : "I will complete this task: “\($0.task)”"))
        })
    }
    public static func isFirstPerson(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^(?:Я\s|I\s|I'm\b|I’m\b)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
