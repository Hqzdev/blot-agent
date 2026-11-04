import Foundation
import Observation

@MainActor @Observable
final class MacDemoSession {
    private(set) var state: MacDemoState
    private(set) var persistenceError: String?
    private let repository: any MacDemoRepository
    private let engine = MacDemoScenarioEngine()
    private let scheduler = MacDemoScheduler()
    private var persistenceEnabled = true

    init(repository: (any MacDemoRepository)? = nil) {
        let repository = repository ?? MacDemoFileRepository.applicationRepository()
        self.repository = repository
        do { state = try repository.load() ?? MacDemoSeed.make() } catch {
            state = MacDemoSeed.make()
            persistenceEnabled = false
            persistenceError =
                "Не удалось прочитать демо. Изменения останутся в текущем сеансе; исходный файл сохранён."
        }
    }

    func update(_ change: (inout MacDemoState) -> Void) {
        var next = state
        change(&next)
        state = next
        guard persistenceEnabled else { return }
        do {
            try repository.save(next)
            persistenceError = nil
        } catch {
            persistenceError = "Не удалось сохранить демо. Проверьте доступное место и права на папку приложения."
        }
    }

    func send(
        _ text: String, conversation: String, agentID: String, groupIDs: [String] = [], attachments: [String] = [],
        replyToID: String? = nil, now: Date = Date()
    ) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        update { state in
            let validReply = state.threads[conversation]?.contains { $0.id == replyToID } == true ? replyToID : nil
            let outgoing = MacDemoMessage(isUser: true, text: text, attachments: attachments, replyToID: validReply)
            state.threads[conversation, default: []].append(outgoing)
            var responses: [MacDemoMessage]
            if !attachments.isEmpty && (text.isEmpty || text.lowercased().contains("прочитай")) {
                responses = state.documents.filter { attachments.contains($0.title) }.map {
                    .init(
                        authorID: agentID, text: "Из документа «\($0.title)»:\n\($0.body)", kind: .document,
                        referenceID: $0.id)
                }
            } else {
                responses = engine.respond(to: text, agentID: agentID, groupIDs: groupIDs, state: &state)
            }
            for index in responses.indices { responses[index].createdAt = now }
            if validReply != nil, !responses.isEmpty { responses[0].replyToID = outgoing.id }
            state.threads[conversation, default: []].append(contentsOf: responses)
            state.settings.usedActions += 1
            if conversation.hasPrefix("agent:"), let index = state.agents.firstIndex(where: { $0.id == agentID }) {
                state.agents[index].preview = responses.last?.text ?? text
                state.agents[index].unread = false
            }
        }
    }

    func saveAgent(_ agent: MacDemoAgent) {
        guard !agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        update { state in
            if let index = state.agents.firstIndex(where: { $0.id == agent.id }) {
                state.agents[index] = agent
            } else {
                state.agents.append(agent)
                state.threads["agent:" + agent.id] = [
                    .init(
                        authorID: agent.id,
                        text:
                            "Привет! Какую область работы мне поручим? Можно выбрать вариант или написать свою задачу.",
                        kind: .onboarding)
                ]
            }
        }
    }

    func configureAgent(_ id: String, role: String) {
        update { state in
            guard let index = state.agents.firstIndex(where: { $0.id == id }) else { return }
            state.agents[index].role = role
            let direction = "Основное направление: \(role.lowercased())."
            if !state.agents[index].instructions.contains(direction) {
                state.agents[index].instructions += "\n" + direction
            }
            state.threads["agent:" + id, default: []].append(.init(isUser: true, text: role))
            state.threads["agent:" + id, default: []].append(
                .init(
                    authorID: id,
                    text: "Беру на себя направление «\(role)». Инструкции сохранены в профиле. С чего начнём?",
                    kind: .suggestions))
        }
    }

    @discardableResult func saveGroup(id: String?, name: String, agentIDs: [String]) -> String? {
        let valid = Array(Set(agentIDs)).filter { id in state.agents.contains { $0.id == id } }.sorted()
        guard valid.count >= 2, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let id = id ?? UUID().uuidString
        update { state in
            let group = MacDemoGroup(id: id, name: name, agentIDs: valid)
            if let index = state.groups.firstIndex(where: { $0.id == id }) {
                state.groups[index] = group
            } else {
                state.groups.append(group)
                state.threads["group:" + id] = [
                    .init(
                        authorID: valid[0],
                        text:
                            "Команда собрана. Дайте общую задачу — мы распределим обязанности и покажем результаты в этой переписке."
                    )
                ]
            }
        }
        return id
    }

    func importTemplate(_ template: MacDemoTemplate) -> String {
        let id = UUID().uuidString
        update { state in
            state.agents.append(
                .init(
                    id: id, name: template.name, role: template.role, instructions: template.instructions,
                    color: template.color, avatarShape: template.shape, preview: "Добавлен из коллекции Blot"))
            state.memories += template.memories.map { .init(id: UUID().uuidString, text: $0, agentID: id) }
            state.skills += template.skills.map {
                .init(id: UUID().uuidString, title: $0, instructions: template.instructions, agentID: id)
            }
            if let title = template.routine {
                state.routines.append(
                    .init(
                        id: UUID().uuidString, title: title, agentID: id, instructions: template.instructions,
                        enabled: false,
                        weekdays: title.contains("понедельник") ? ["Пн"] : ["Пн", "Вт", "Ср", "Чт", "Пт"]))
            }
            state.threads["agent:" + id] = [
                .init(
                    authorID: id,
                    text:
                        "Я в команде. Инструкции, память и навыки импортированы. Уточните задачу или выберите направление.",
                    kind: .onboarding)
            ]
        }
        return id
    }

    func saveRoutine(_ routine: MacDemoRoutine) {
        guard scheduler.validTime(routine.time), !routine.title.isEmpty, !routine.instructions.isEmpty else { return }
        update { state in
            if let index = state.routines.firstIndex(where: { $0.id == routine.id }) {
                state.routines[index] = routine
            } else {
                state.routines.append(routine)
            }
        }
    }

    func runRoutine(_ id: String, now: Date = Date()) {
        guard let routine = state.routines.first(where: { $0.id == id }) else { return }
        update { state in
            guard let index = state.routines.firstIndex(where: { $0.id == id }) else { return }
            state.routines[index].lastRun = now
            let noNews =
                routine.instructions.lowercased().contains("почт")
                && state.emails.filter { $0.agentID != "support" }.allSatisfy(\.sent)
            if routine.quiet && noNews { return }
            var result = engine.respond(
                to: routine.instructions, agentID: routine.agentID, allowScheduling: false, state: &state)
            if !routine.requiresApproval {
                let emailIDs = Set(result.filter { $0.kind == .email }.compactMap(\.referenceID))
                for emailID in emailIDs {
                    guard canSendEmail(emailID), let emailIndex = state.emails.firstIndex(where: { $0.id == emailID }),
                        !state.emails[emailIndex].sent
                    else { continue }
                    state.emails[emailIndex].sent = true
                    result.append(
                        .init(
                            authorID: routine.agentID,
                            text: "Демо-ответ отправлен без дополнительного согласования: "
                                + state.emails[emailIndex].sender, kind: .email, referenceID: emailID))
                }
            }
            result.insert(.init(authorID: routine.agentID, text: "Запуск расписания «\(routine.title)»"), at: 0)
            for offset in result.indices { result[offset].createdAt = now }
            state.threads["agent:" + routine.agentID, default: []].append(contentsOf: result)
            if let agentIndex = state.agents.firstIndex(where: { $0.id == routine.agentID }) {
                state.agents[agentIndex].preview = result.last?.text ?? routine.title
                state.agents[agentIndex].unread = state.settings.notifications && state.agents[agentIndex].notifications
            }
            state.settings.usedActions += 1
        }
    }

    func runDueRoutines(now: Date = Date()) {
        if now >= state.settings.usageResetAt {
            update {
                $0.settings.usedActions = 0
                $0.settings.usageResetAt =
                    Calendar.current.dateInterval(of: .weekOfYear, for: now)?.end ?? now.addingTimeInterval(604800)
            }
        }
        let due = state.routines.filter { scheduler.isDue($0, at: now) }.map(\.id)
        for id in due { runRoutine(id, now: now) }
    }

    func saveConnection(_ connection: MacDemoConnection) {
        guard !connection.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        update { state in
            if let index = state.connections.firstIndex(where: { $0.id == connection.id }) {
                let oldLabel = state.connections[index].label
                if connection.pluginID == "gmail", oldLabel != connection.label {
                    for emailIndex in state.emails.indices where state.emails[emailIndex].accountLabel == oldLabel {
                        state.emails[emailIndex].accountLabel = connection.label
                    }
                }
                state.connections[index] = connection
            } else {
                state.connections.append(connection)
            }
        }
    }

    @discardableResult func sendEmail(_ id: String, subject: String, reply: String, conversation: String) -> Bool {
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let email = state.emails.first(where: { $0.id == id }), !email.sent
        else { return false }
        guard canSendEmail(id) else { return false }
        update { state in
            guard let index = state.emails.firstIndex(where: { $0.id == id }) else { return }
            state.emails[index].subject = subject
            state.emails[index].reply = reply
            state.emails[index].sent = true
            state.threads[conversation, default: []].append(
                .init(
                    authorID: email.agentID,
                    text:
                        "Демо-ответ отправлен: \(email.sender), цепочка «\(subject)». Настоящее письмо не отправлялось.",
                    kind: .email, referenceID: id))
            state.settings.usedActions += 1
        }
        return true
    }

    func saveEmailDraft(_ id: String, subject: String, reply: String) {
        update { state in
            guard let index = state.emails.firstIndex(where: { $0.id == id }) else { return }
            state.emails[index].subject = subject
            state.emails[index].reply = reply
        }
    }

    func canSendEmail(_ id: String) -> Bool {
        guard let email = state.emails.first(where: { $0.id == id }) else { return false }
        let service = email.agentID == "support" ? "freshdesk" : "gmail"
        return state.connections.contains {
            $0.pluginID == service && $0.allowSend && ($0.label == email.accountLabel || service == "freshdesk")
        }
    }

    func addToCart(_ productID: String) {
        guard state.products.contains(where: { $0.id == productID }), !(state.cart ?? []).contains(productID) else {
            return
        }
        update { $0.cart = ($0.cart ?? []) + [productID] }
    }

    @discardableResult func checkoutDemoOrder(conversation: String, agentID: String) -> String? {
        let products = state.products.filter { (state.cart ?? []).contains($0.id) }
        guard !products.isEmpty else { return nil }
        let id = UUID().uuidString
        let total = products.reduce(0) { $0 + $1.price }
        let lines = products.map { $0.name + " · $" + String(format: "%.2f", $0.price) }.joined(separator: "\n")
        update { state in
            state.documents.append(
                .init(
                    id: id, title: "Демо-заказ.txt",
                    body: lines + "\n\nИтого: $" + String(format: "%.2f", total)
                        + "\n\nЭто локальный демо-заказ. Оплата, покупка и доставка не выполнялись.", agentID: agentID))
            state.cart = []
            state.threads[conversation, default: []].append(
                .init(
                    authorID: agentID, text: "Демо-заказ сохранён в документах. Настоящая покупка не выполнялась.",
                    kind: .document, referenceID: id))
        }
        return id
    }
}
