import BlotDomain
import Foundation
import Observation

struct MacAgentQuestion {
    let id = UUID()
    let title: String
    let choices: [String]

    static var meals: Self { Self(title: "What should we start with?", choices: [
        "Plan this week’s dinners", "Find something for tonight", "Turn a recipe into a grocery list", "Just hang out until I need you"
    ]) }
}

struct MacConversationBlock: Identifiable {
    enum Position: Equatable { case top, after(UUID) }
    enum Kind {
        case question(MacAgentQuestion)
        case received(conversationID: UUID)
        case sent(conversationID: UUID)
        case recipePreview
    }
    let id = UUID()
    let position: Position
    let kind: Kind
}

@MainActor @Observable
final class MacConversationPresentation {
    enum Status: Equatable { case needsApproval }
    private var blocks: [UUID: [MacConversationBlock]] = [:]
    private(set) var answers: [UUID: String] = [:]
    private var featuredAgents: [UUID: UUID] = [:]
    private var sidebarOrders: [UUID: [UUID]] = [:]
    private var statuses: [UUID: Status] = [:]

    func blocks(at position: MacConversationBlock.Position, in conversationID: UUID?) -> [MacConversationBlock] {
        guard let conversationID else { return [] }
        return (blocks[conversationID] ?? []).filter { $0.position == position }
    }
    func sidebarOrder(in conversationID: UUID?) -> [UUID] { conversationID.flatMap { sidebarOrders[$0] } ?? [] }
    func prefersWideLayout(_ conversationID: UUID) -> Bool { featuredAgents[conversationID] != nil }
    func status(in conversationID: UUID) -> Status? { statuses[conversationID] }
    func forgetConversation(_ id: UUID) {
        blocks[id] = nil; featuredAgents[id] = nil; sidebarOrders[id] = nil; statuses[id] = nil
        for key in Array(sidebarOrders.keys) { sidebarOrders[key]?.removeAll { $0 == id } }
        for key in Array(blocks.keys) {
            blocks[key]?.removeAll {
                switch $0.kind { case .received(let target), .sent(let target): target == id; default: false }
            }
        }
    }
    func answered(_ questionID: UUID, text: String) { answers[questionID] = text }
    func reset() { blocks = [:]; answers = [:]; featuredAgents = [:]; sidebarOrders = [:]; statuses = [:] }

    func prepareFirstConversation(_ conversationID: UUID, agent: BlotV3.AgentProfile) {
        guard blocks[conversationID] == nil else { return }
        let foodRole = agent.roleId == "meal-planner" || ["chef", "повар", "шеф"].contains { agent.name.localizedCaseInsensitiveContains($0) }
        let question = foodRole ? MacAgentQuestion.meals : MacAgentQuestion(title: "What should we start with?", choices: [
            "Plan a task", "Answer a question", "Review a document", "Just hang out until I need you"
        ])
        blocks[conversationID] = [.init(position: .top, kind: .question(question))]
    }

    func configureDemo(_ snapshot: WorkspaceSnapshot) {
        func conversation(_ name: String) -> BlotV3.Conversation? {
            guard let agent = snapshot.agents.first(where: { $0.name == name }) else { return nil }
            return snapshot.conversations.first { $0.agentId == agent.metadata.id }
        }
        guard let chef = conversation("Sous Chef"), let content = conversation("Content"),
              let sink = snapshot.agents.first(where: { $0.name == "Sink" }),
              let last = snapshot.messages.last(where: { $0.conversationId == chef.metadata.id }) else { return }
        blocks[chef.metadata.id] = [
            .init(position: .top, kind: .question(.meals)),
            .init(position: .top, kind: .received(conversationID: content.metadata.id)),
            .init(position: .after(last.metadata.id), kind: .recipePreview),
            .init(position: .after(last.metadata.id), kind: .sent(conversationID: content.metadata.id))
        ]
        blocks[content.metadata.id] = [.init(position: .top, kind: .received(conversationID: chef.metadata.id))]
        let order = ["Content", "Sous Chef", "Travel", "Inbox Manager", "Feedback Router", "Scout", "Housing"]
            .compactMap { conversation($0)?.metadata.id }
        for id in order + [conversation("Sink")?.metadata.id].compactMap({ $0 }) {
            featuredAgents[id] = sink.metadata.id
            sidebarOrders[id] = order
        }
        if let feedback = conversation("Feedback Router") { statuses[feedback.metadata.id] = .needsApproval }
    }

    func context(in conversationID: UUID?, snapshot: WorkspaceSnapshot) -> [String] {
        guard let conversationID else { return [] }
        let related = Set((blocks[conversationID] ?? []).compactMap { block -> UUID? in
            switch block.kind {
            case .received(let id), .sent(let id): id
            default: nil
            }
        })
        return snapshot.messages.filter { related.contains($0.conversationId) }.map { message in
            let agentID = snapshot.conversations.first { $0.metadata.id == message.conversationId }?.agentId
            let name = snapshot.agents.first { $0.metadata.id == agentID }?.name ?? "Blot Agent"
            return "\(name), \(message.role.rawValue): \(String(message.content.prefix(2000)))"
        }
    }
}
