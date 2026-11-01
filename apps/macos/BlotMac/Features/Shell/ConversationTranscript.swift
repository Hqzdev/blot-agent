import BlotDesign
import Foundation

enum ConversationTranscript {
    static func text(_ blocks: [ThreadBlock]) -> String {
        blocks.map { block in
            switch block {
            case .user(let text): "You: " + text
            case .agent(let text): "Blot: " + text
            case .note(_, let text): text
            case .steps(let rows): rows.map { $0.verb + " " + $0.target + " " + $0.meta }.joined(separator: "\n")
            case .terminal(let command, let exit, let lines):
                "$ " + command + "\n" + lines.map(\.text).joined(separator: "\n") + "\nExit: \(exit)"
            case .plan(let title, let items): title + "\n" + items.map { "• " + $0.text }.joined(separator: "\n")
            case .approval(let request): "Approval: " + request.title + "\n" + request.command
            case .changes(let files): files.map { "\($0.path) +\($0.added) −\($0.removed)" }.joined(separator: "\n")
            }
        }.joined(separator: "\n\n")
    }
}

extension AppState {
    func transcript(for item: SidebarConversation) -> String {
        let body: String
        switch item.kind {
        case .task: body = UUID(uuidString: item.taskID).map { ConversationTranscript.text(transcriptBlocks($0)) } ?? ""
        case .chat:
            body = (workChat.session(item.taskID)?.messages ?? []).map {
                ($0.fromUser ? "You: " : "Blot: ") + $0.text
            }.joined(separator: "\n\n")
        case .team:
            body = UUID(uuidString: item.taskID).map { ConversationTranscript.text(transcriptBlocks($0)) } ?? ""

        }
        return item.title + "\n\n" + body
    }
}
