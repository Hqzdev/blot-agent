import AppKit
import Foundation

extension MacTeamPresentation {
    var replyingTo: MacDemoMessage? { messages.first { $0.id == replyToID } }

    func authorName(of message: MacDemoMessage) -> String {
        message.isUser ? "Вы" : agents.first { $0.id == message.authorID }?.name ?? "Агент"
    }

    func messageText(_ message: MacDemoMessage) -> String {
        MacDemoMessageText.plain(message.text, agents: agents)
    }

    func reply(to message: MacDemoMessage) {
        replyToID = message.id
        composerFocusRequest += 1
    }

    func react(_ emoji: String, to message: MacDemoMessage) {
        demo.toggleReaction(emoji, messageID: message.id, conversation: conversationKey)
    }

    func copy(_ message: MacDemoMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(messageText(message), forType: .string)
    }

    func remember(_ message: MacDemoMessage) {
        let text = messageText(message)
        guard !demo.state.memories.contains(where: { $0.text == text }) else { return }
        demo.update {
            $0.memories.append(.init(id: UUID().uuidString, text: text, agentID: group == nil ? agent.id : nil))
        }
    }
}
