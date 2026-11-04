import Foundation

struct MacDemoScenarioEngine {
    func respond(
        to request: String, agentID: String, groupIDs: [String] = [], allowScheduling: Bool = true,
        isSkillRun: Bool = false,
        state: inout MacDemoState
    ) -> [MacDemoMessage] {
        let text = request.lowercased()
        let author = state.agents.first { $0.id == agentID } ?? state.agents[0]
        let draftableMailLabels = Set(
            state.connections.filter { $0.pluginID == "gmail" && $0.allowRead && $0.allowDraft }.map(\.label))
        let readableServices = Set(state.connections.filter(\.allowRead).map(\.pluginID))
        func reply(_ text: String, _ kind: MacDemoMessage.Kind = .text, _ reference: String? = nil) -> [MacDemoMessage]
        {
            [.init(authorID: author.id, text: text, kind: kind, referenceID: reference)]
        }
        if text.hasPrefix("/"), !isSkillRun,
            let skill = state.skills.first(where: {
                $0.title.caseInsensitiveCompare(String(request.dropFirst())) == .orderedSame
            })
        {
            var messages = respond(
                to: skill.instructions, agentID: skill.agentID, groupIDs: groupIDs, allowScheduling: false,
                isSkillRun: true, state: &state)
            messages.insert(
                .init(authorID: skill.agentID, text: "Выполняю навык «\(skill.title)» по сохранённым инструкциям."),
                at: 0)
            return messages
        }
        if ["открой сайт", "браузер", "на компьютере", "рабочий стол", "в интернете", "search the web"].contains(
            where: text.contains)
        {
            return reply(
                "Управление компьютером и интернет отключены. В демо доступны переписка, расписания, почта, документы и сравнение сохранённых вариантов.",
                .suggestions)
        }
        if text.contains("подключ") || text.contains("connect") || text.contains("добавь аккаунт") {
            let service =
                ["gmail", "slack", "notion", "quickbooks", "freshdesk", "composio", "zapier", "1password", "beehiiv"]
                .first(where: text.contains) ?? "gmail"
            return reply(
                "Добавим демо-подключение. Выберите аккаунт и задайте ему метку — настоящий вход в сервис не потребуется.",
                .connection, service)
        }
        if ["твоя задача", "отвечай", "пиши", "будь моим"].contains(where: text.hasPrefix) {
            if let index = state.agents.firstIndex(where: { $0.id == author.id }) {
                state.agents[index].instructions += "\n" + request
            }
            return reply("Добавил указание в инструкции агента: «\(request)».")
        }
        if text.contains("запомни") || text.contains("remember") {
            let value = request.replacingOccurrences(of: "запомни", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "remember", with: "", options: .caseInsensitive).trimmingCharacters(
                    in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !value.isEmpty else {
                return reply("Что нужно запомнить? Напишите, например: «Запомни: пиши коротко и по делу».")
            }
            let scope: String? = text.contains("для всех") || text.contains("общая") ? nil : author.id
            if !state.memories.contains(where: { $0.text == value && $0.agentID == scope }) {
                state.memories.append(.init(id: UUID().uuidString, text: value, agentID: scope))
            }
            return reply(
                "Запомнил: \(value). Это предпочтение сохранено в \(scope == nil ? "общей памяти команды" : "памяти агента")."
            )
        }
        if allowScheduling
            && (text.contains("кажд") || text.contains("по будням") || text.contains("расписан")
                || text.contains("every morning"))
        {
            let time = requestedTime(text)
            let frequency =
                text.contains("каждый час") || text.contains("every hour")
                ? "Каждый час"
                : text.contains("пятниц") ? "По пятницам" : text.contains("каждый день") ? "Каждый день" : "По будням"
            let title =
                text.contains("почт") || text.contains("обзор") || text.contains("slack") || text.contains("утр")
                ? "Утренний обзор" : text.contains("расход") ? "Проверка расходов" : String(request.prefix(50))
            let existing = state.routines.firstIndex { $0.agentID == author.id && $0.title == title }
            var routine =
                existing.map { state.routines[$0] }
                ?? .init(id: UUID().uuidString, title: title, agentID: author.id, instructions: request)
            routine.time = time
            routine.frequency = frequency
            routine.enabled = true
            if text.contains("понедельник") { routine.weekdays = ["Пн"] }
            if !routine.instructions.contains(request) { routine.instructions += "\n" + request }
            if let existing { state.routines[existing] = routine } else { state.routines.append(routine) }
            return reply(
                existing == nil
                    ? "Создал расписание. \(routine.schedule). Результаты появятся в этой переписке."
                    : "Обновил существующее расписание на \(time), чтобы не присылать два одинаковых обзора.", .routine,
                routine.id)
        }
        if text.contains("создай") && (text.contains("бот") || text.contains("агент")) {
            let role =
                text.contains("финанс")
                ? "Финансы"
                : text.contains("контент") ? "Контент" : text.contains("исслед") ? "Исследования" : "Ассистент"
            let name = quotedName(request) ?? "Новый \(role.lowercased())"
            let id = UUID().uuidString
            state.agents.append(
                .init(
                    id: id, name: name, role: role, instructions: request, color: "teal", avatarShape: "round",
                    preview: "Выберите область ответственности"))
            state.threads["agent:" + id] = [
                .init(authorID: id, text: "Привет! Какую работу мне поручим?", kind: .onboarding)
            ]
            return reply(
                "Создал агента «\(name)». Откройте его профиль, чтобы уточнить имя, роль и инструкции.", .agentCreated,
                id)
        }
        if text.contains("предлож") && (text.contains("автомат") || text.contains("задач")) {
            return reply(
                "Предлагаю три задачи: утренний обзор почты и Slack, проверку неоплаченных счетов по пятницам и подготовку контент-плана по понедельникам. Выберите, что настроить.",
                .suggestions)
        }
        if !groupIDs.isEmpty && ["счет", "счёт", "неоплач", "invoice", "финанс"].contains(where: text.contains) {
            guard readableServices.contains("quickbooks") else {
                return reply(
                    "Для проверки счетов разрешите чтение в демо-подключении QuickBooks.", .connection, "quickbooks")
            }
            let members = groupIDs.compactMap { id in state.agents.first { $0.id == id } }
            let lead = members.first { $0.role == "Координатор" } ?? members.first ?? author
            let finance = members.first { $0.role.contains("Финанс") } ?? members.last ?? lead
            let mail = members.first { $0.role.contains("Почт") } ?? lead
            return [
                .init(
                    authorID: lead.id,
                    text:
                        "\(MacDemoMessageText.mention(finance.id)), собери неоплаченные счета и сроки. \(MacDemoMessageText.mention(mail.id)) подготовит письма, чтобы клиенты не получили повторные напоминания."
                ),
                .init(
                    authorID: finance.id,
                    text: "В демо-реестре два открытых счёта на $1,840. Один просрочен на пять дней.", kind: .invoices),
                .init(
                    authorID: mail.id,
                    text:
                        state.emails.first(where: { $0.id == "invoice-north" })?.sent == true
                        ? "Напоминание уже отправлено в демо. Повторно клиенту не пишу."
                        : "Беру письма и последующие напоминания. Подготовил один черновик, отправку оставил на согласование.",
                    kind: .email, referenceID: "invoice-north"),
                .init(
                    authorID: lead.id,
                    text:
                        "Обязанности распределены. Счета проверяет \(MacDemoMessageText.mention(finance.id)), коммуникации ведёт \(MacDemoMessageText.mention(mail.id)). Все результаты остаются в этом чате."
                ),
            ]
        }
        if !groupIDs.isEmpty {
            let members = groupIDs.compactMap { id in state.agents.first { $0.id == id } }
            let lead = members.first { $0.role == "Координатор" } ?? members.first ?? author
            var result = [
                MacDemoMessage(
                    authorID: lead.id,
                    text:
                        "Я соберу результаты. " + members.filter { $0.id != lead.id }.map {
                            MacDemoMessageText.mention($0.id) + ", подготовь свою часть по направлению «" + $0.role + "»."
                        }.joined(separator: " ")
                )
            ]
            for member in members where member.id != lead.id {
                result += respond(to: request, agentID: member.id, allowScheduling: false, state: &state)
            }
            result.append(
                .init(
                    authorID: lead.id,
                    text:
                        "Результаты команды собраны. Можно открыть карточки, проверить материалы и уточнить следующий шаг."
                ))
            return result
        }
        if (text.contains("отправь") || text.contains("напиши")) && text.contains("slack") {
            guard state.connections.contains(where: { $0.pluginID == "slack" && $0.allowSend }) else {
                return reply(
                    "Разрешите отправку в демо-подключении Slack, затем повторите запрос.", .connection, "slack")
            }
            state.threads["service:slack", default: []].append(.init(authorID: author.id, text: request))
            return reply("Демо-сообщение сохранено в Slack: «\(request)». Внешняя отправка не выполнялась.")
        }
        if text.contains("поделись") || text.contains("дай доступ") {
            guard let document = state.documents.last else {
                return reply("Сначала создайте документ, которым нужно поделиться.")
            }
            state.threads["service:drive", default: []].append(
                .init(
                    authorID: author.id, text: "Демо-доступ для команды: " + document.title, kind: .document,
                    referenceID: document.id))
            return reply(
                "Сохранил демо-доступ для команды к «\(document.title)». Настройки реального файла не менялись.",
                .document, document.id)
        }
        if text.contains("саунд") || text.contains("товар") || text.contains("amazon") || text.contains("сравни")
            || author.role.contains("Исслед")
        {
            return reply(
                "Подготовил сравнение в пределах вашего бюджета на сохранённых демо-данных. Цены и отзывы не запрашивались у магазина.",
                .products, String(requestedBudget(text)))
        }
        if text.contains("письм") || text.contains("почт") || text.contains("лиз") || text.contains("lisa")
            || text.contains("email") || author.role == "Почта"
        {
            let readable = state.connections.filter { $0.pluginID == "gmail" && $0.allowRead }
            if readable.isEmpty {
                return reply("Для демо-почты нужно подключение Gmail с разрешением на чтение.", .connection, "gmail")
            }
            if !readable.contains(where: \.allowDraft) {
                return reply(
                    "Чтение доступно, но подготовка ответов отключена в разрешениях. Измените доступ демо-аккаунта.",
                    .connection, "gmail")
            }
        }
        if text.contains("лиз") || text.contains("lisa") {
            guard let email = state.emails.first(where: { $0.id == "lisa" }),
                draftableMailLabels.contains(email.accountLabel)
            else {
                return reply(
                    "Для этого почтового аккаунта нужно разрешение на чтение и подготовку ответов.", .connection,
                    "gmail")
            }
            return reply(
                "Подготовил короткую благодарность Лизе в существующей цепочке. Проверьте текст перед демо-отправкой.",
                .email, "lisa")
        }
        if text.contains("письм") || text.contains("почт") || text.contains("email") || author.role == "Почта" {
            let pending = state.emails.filter {
                !$0.sent && $0.agentID != "support" && !$0.id.hasPrefix("invoice-")
                    && draftableMailLabels.contains($0.accountLabel)
            }
            if pending.isEmpty {
                return reply(
                    "В доступных демо-аккаунтах нет писем без ответа. Согласованные ответы находятся в истории переписки."
                )
            }
            return pending.map {
                .init(
                    authorID: author.id, text: "\($0.sender) · \($0.accountLabel). \($0.incoming)", kind: .email,
                    referenceID: $0.id)
            }
        }
        if text.contains("счёт") || text.contains("счет") || text.contains("неоплач") || text.contains("invoice") {
            guard readableServices.contains("quickbooks") else {
                return reply("Для проверки счетов разрешите чтение в QuickBooks.", .connection, "quickbooks")
            }
            return reply(
                "Два счёта ожидают оплаты: North Studio — $1,240, Green Market — $600. Подготовлю одно напоминание по каждой цепочке.",
                .invoices)
        }
        if text.contains("расход") || text.contains("операци") || text.contains("финанс") || author.role == "Финансы" {
            guard readableServices.contains("quickbooks") else {
                return reply("Подключите демо-аккаунт QuickBooks с доступом на чтение.", .connection, "quickbooks")
            }
            return reply(
                state.transactions.allSatisfy(\.approved)
                    ? "Все операции согласованы. Категории сохранены в демо-реестре."
                    : "Нашёл три операции. Подобрал категории по описаниям и подготовил их для проверки.", .transactions
            )
        }
        if text.contains("поддерж") || text.contains("регламент") || author.role == "Поддержка" {
            guard readableServices.contains("freshdesk") else {
                return reply("Для обращений поддержки нужен доступ на чтение Freshdesk.", .connection, "freshdesk")
            }
            return reply(
                "Прочитал сохранённый регламент. В ответе уточнил номер заказа и интервал доставки.", .email, "support")
        }
        if text.contains("встреч") || text.contains("календар") {
            guard readableServices.contains("calendar") else {
                return reply("Для календаря подключите демо-аккаунт Google Calendar.", .connection, "calendar")
            }
            if text.contains("создай") || text.contains("добавь") || text.contains("запланируй") {
                let event = requestedTime(text) + " · " + request
                state.events.append(event)
                return reply("Добавил встречу в демо-календарь: \(event).", .event)
            }
            return reply("В демо-календаре: \(state.events.joined(separator: "; ")).", .event)
        }
        if text.contains("рассыл") || text.contains("контент") || text.contains("документ") || text.contains("стать")
            || author.role == "Контент"
        {
            let id = UUID().uuidString
            let title = text.contains("план") ? "Контент-план.md" : "Новый материал.md"
            let body =
                text.contains("план")
                ? "Понедельник — полезный совет\nСреда — история проекта\nПятница — короткая рассылка с итогами недели"
                : "Тема: \(request)\n\nЧто изменилось\nКоманда собрала важный контекст и подготовила следующие шаги.\n\nЧто попробовать\nВыберите одну повторяющуюся задачу и начните с понятного результата.\n\nСледующий шаг\nОтветьте, какая задача сейчас отнимает больше всего времени."
            state.documents.append(.init(id: id, title: title, body: body, agentID: author.id))
            return reply(
                "Подготовил материал на основе локального контекста. Откройте документ, чтобы изменить текст и сохранить результат.",
                .document, id)
        }
        if text.contains("slack") || text.contains("обзор") || text.contains("сводк") || text.hasPrefix("/") {
            return reply(
                "Проверил демо-данные трёх пространств Slack, почты и календаря. Требуют внимания: новый заказ, согласование макетов и два неоплаченных счёта.",
                .briefing)
        }
        return reply(
            "Принял задачу: «\(request)». В демо могу показать готовые сценарии почты, расписаний, документов и работы команды. Выберите следующий шаг или уточните направление.",
            .suggestions)
    }

    private func requestedBudget(_ text: String) -> Double {
        let expression = try? NSRegularExpression(pattern: #"(?:до|under|бюджет|<)\s*\$?\s*(\d+(?:[.,]\d+)?)"#)
        guard let match = expression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text),
            let value = Double(text[range].replacingOccurrences(of: ",", with: ".")), value > 0
        else { return 500 }
        return value
    }

    private func requestedTime(_ text: String) -> String {
        if let range = text.range(of: #"\b([01]?\d|2[0-3]):[0-5]\d\b"#, options: .regularExpression) {
            let value = String(text[range])
            return value.count == 4 ? "0" + value : value
        }
        if let range = text.range(of: #"(?:в|at)\s+([01]?\d|2[0-3])\b"#, options: .regularExpression),
            let hour = text[range].split(separator: " ").last, let number = Int(hour)
        {
            return String(format: "%02d:00", number)
        }
        return "09:00"
    }

    private func quotedName(_ text: String) -> String? {
        guard let start = text.firstIndex(where: { "«\"".contains($0) }),
            let end = text[text.index(after: start)...].firstIndex(where: { "»\"".contains($0) })
        else { return nil }
        let value = String(text[text.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
