import Foundation

/// Workers execute the current plan and discussion, without imitating old chat turns.
public struct WorkspaceGroupWorkerContext: Sendable {
    public init() {}
    public func messages(prepared: [ChatModelMessage], agentName: String, task: String, attachmentContext: ChatModelMessage? = nil) -> [ChatModelMessage] {
        var result = prepared.filter { $0.role == "system" }
        if let attachmentContext { result.append(attachmentContext) }
        // The coordinator already resolved the task using history. Its current plan,
        // this turn's discussion and approved memory are supplied in the system context.
        // Replaying old assistant replies here teaches models to imitate stale results.
        result.append(.init(role: "user", content: """
        Original group request, quoted only for constraints and attachments. Other members' tasks are not yours:
        \(prepared.last?.content ?? "")
        """))
        result.append(.init(role: "user", content: """
        Your active assignment as \(agentName): \(task)
        Speak as yourself in first person. If describing your next action say "Я проверю…" / "I will…"; for confirmed work say "Я проверил…" / "I checked…". Do not refer to yourself by role, give yourself orders, or reproduce the assignment as your reply.
        Complete only this assignment now, respecting ALL constraints in the latest request. Earlier tasks are history, not current work. Use actual tools for requested checks/actions; a colleague's claim is not evidence that you checked your app. Do not answer for another member or repeat an old result.
        """))
        return result
    }
}
