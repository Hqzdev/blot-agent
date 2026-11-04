import Foundation

extension MacDemoSession {
    func toggleReaction(_ emoji: String, messageID: String, conversation: String,
                        authorID: String = MacDemoReaction.userID) {
        guard MacDemoReaction.choices.contains(emoji),
              authorID == MacDemoReaction.userID || state.agents.contains(where: { $0.id == authorID }),
              let index = state.threads[conversation]?.firstIndex(where: { $0.id == messageID }) else { return }
        update { state in
            guard var thread = state.threads[conversation] else { return }
            var reactions = thread[index].reactions ?? []
            let selected = reactions.contains { $0.authorID == authorID && $0.emoji == emoji }
            reactions.removeAll { $0.authorID == authorID }
            if !selected { reactions.append(.init(emoji: emoji, authorID: authorID)) }
            thread[index].reactions = reactions.isEmpty ? nil : reactions
            state.threads[conversation] = thread
        }
    }

    /// Each existing or new group gets one local example, without replacing its history.
    func prepareCollaboration(in groupID: String) {
        let key = "group:" + groupID
        guard let group = state.groups.first(where: { $0.id == groupID }),
              !(state.threads[key] ?? []).contains(where: { $0.referenceID == MacDemoCollaboration.referenceID }) else { return }
        let messages = MacDemoCollaboration.messages(members: group.agentIDs.compactMap { id in
            state.agents.first { $0.id == id }
        })
        guard !messages.isEmpty else { return }
        update { $0.threads[key, default: []].append(contentsOf: messages) }
    }
}

enum MacDemoCollaboration {
    static let referenceID = "collaboration-demo-v1"

    static func messages(members: [MacDemoAgent]) -> [MacDemoMessage] {
        guard members.count >= 2, let lead = members.first(where: { $0.role == "Координатор" }) ?? members.first else { return [] }
        let workers = members.filter { $0.id != lead.id }
        let mention = MacDemoMessageText.mention
        let request = MacDemoMessage(isUser: true, text: "Команда, распределите задачи и покажите, как вы работаете вместе.", referenceID: referenceID)
        var assignment = MacDemoMessage(authorID: lead.id,
            text: "Я соберу общий план и проверю результат. " + workers.map {
                "\(mention($0.id)), \(task(for: $0))."
            }.joined(separator: " "), replyToID: request.id)
        assignment.reactions = workers.map { .init(emoji: "👍", authorID: $0.id) }
        var result = [request, assignment]
        for worker in workers {
            var reply = MacDemoMessage(authorID: worker.id,
                text: "\(mention(lead.id)), беру направление «\(worker.role)». Как закончу, передам результат сюда.",
                replyToID: assignment.id)
            reply.reactions = [.init(emoji: "✅", authorID: lead.id)]
            result.append(reply)
        }
        result.append(.init(authorID: lead.id,
            text: "Договорились, " + workers.map { mention($0.id) }.joined(separator: " и ")
                + ". Все части соберём в этом чате. На любое сообщение можно ответить или поставить реакцию.",
            replyToID: result.last?.id))
        return result
    }

    private static func task(for agent: MacDemoAgent) -> String {
        let role = agent.role.lowercased()
        if role.contains("почт") { return "подготовь ответы клиентам" }
        if role.contains("финанс") { return "проверь счета и сроки оплаты" }
        if role.contains("контент") { return "подготовь черновик публикации" }
        if role.contains("исслед") { return "сравни варианты и выдели главное" }
        if role.contains("поддерж") { return "проверь обращения и подготовь ответы" }
        return "подготовь свою часть по направлению «\(agent.role)»"
    }
}
