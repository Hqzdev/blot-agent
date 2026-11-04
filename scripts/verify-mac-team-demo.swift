import Foundation

@main @MainActor
enum VerifyMacTeamDemo {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: " + message) }
        checks += 1
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("blot-demo-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MacDemoFileRepository(url: directory.appendingPathComponent("workspace.json"))
        let demo = MacDemoSession(repository: repository)
        let inboxBefore = demo.state.threads["agent:inbox"]?.count
        demo.send("Запомни: для всех пиши по-русски", conversation: "agent:chief", agentID: "chief")
        check(demo.state.memories.last?.agentID == nil, "shared memory scope")
        let memories = demo.state.memories.count
        demo.send("Запомни: для всех пиши по-русски", conversation: "agent:chief", agentID: "chief")
        check(demo.state.memories.count == memories, "memory deduplication")
        check(demo.state.threads["agent:inbox"]?.count == inboxBefore, "independent conversations")

        let routinesBefore = demo.state.routines.count
        demo.send("Каждое утро в 10:30 присылай обзор почты и Slack", conversation: "agent:chief", agentID: "chief")
        check(demo.state.routines.count == routinesBefore, "merge an existing morning routine")
        check(demo.state.routines.first { $0.id == "brief" }?.time == "10:30", "parse routine time")
        demo.runRoutine("brief")
        check(demo.state.routines.count == routinesBefore, "running a routine must not schedule another routine")
        check(demo.state.routines.first { $0.id == "brief" }?.lastRun != nil, "routine run history")

        let group = demo.saveGroup(id: nil, name: "Демо-команда", agentIDs: ["chief", "finance", "inbox", "finance"])!
        check(demo.state.groups.first { $0.id == group }?.agentIDs.count == 3, "unique group members")
        check(demo.saveGroup(id: nil, name: "Нельзя", agentIDs: ["chief"]) == nil, "require two group members")
        let chiefPreview = demo.state.agents.first { $0.id == "chief" }?.preview
        demo.send("Разберите неоплаченные счета", conversation: "group:" + group, agentID: "chief", groupIDs: ["chief", "finance", "inbox"])
        check(demo.state.agents.first { $0.id == "chief" }?.preview == chiefPreview, "group activity does not replace a personal preview")
        let authors = Set(demo.state.threads["group:" + group, default: []].compactMap(\.authorID))
        check(authors == ["chief", "finance", "inbox"], "delegation uses the selected participants")
        check(demo.state.threads["group:" + group]?.contains { $0.kind == .invoices } == true, "group invoice result")

        demo.saveEmailDraft("lisa", subject: "Re: План", reply: "Лиза, спасибо!")
        check(demo.state.emails.first { $0.id == "lisa" }?.reply == "Лиза, спасибо!", "save edited draft")
        check(demo.sendEmail("lisa", subject: "Re: План", reply: "Лиза, спасибо!", conversation: "agent:inbox"), "local email send")
        let sentCount = demo.state.threads["agent:inbox"]?.count
        check(!demo.sendEmail("lisa", subject: "Re: План", reply: "Повтор", conversation: "agent:inbox"), "prevent duplicate sends")
        check(demo.state.threads["agent:inbox"]?.count == sentCount, "no duplicate confirmation")
        demo.update { state in for index in state.connections.indices { state.connections[index].allowSend = false } }
        check(!demo.sendEmail("anna", subject: "Ответ", reply: "Спасибо", conversation: "agent:inbox"), "respect account send permission")
        check(demo.state.emails.first { $0.id == "anna" }?.sent == false, "blocked send does not change email")

        let template = MacDemoTemplates.all.first { $0.id == "content-strategy" }!
        let imported = demo.importTemplate(template)
        check(demo.state.agents.contains { $0.id == imported }, "import template agent")
        check(demo.state.skills.filter { $0.agentID == imported }.count == template.skills.count, "import template skills")
        check(demo.state.memories.contains { $0.agentID == imported }, "import template memory")
        check(demo.state.routines.first { $0.agentID == imported }?.enabled == false, "import routines paused")
        demo.configureAgent(imported, role: "Контент")
        check(demo.state.agents.first { $0.id == imported }?.instructions.contains(template.instructions) == true, "onboarding preserves template instructions")
        check(demo.state.routines.first { $0.agentID == imported }?.weekdays == ["Пн"], "weekly template runs on Monday")
        check(demo.state.agents.first { $0.id == imported }?.instructions.contains("контент") == true, "onboarding configures instructions")
        var customAgent = MacDemoAgent(id: "custom", name: "Новый специалист", role: "Ассистент", instructions: "Уточняй задачу", color: "teal", avatarShape: "round", preview: "Начнём")
        demo.saveAgent(customAgent)
        check(demo.state.threads["agent:custom"]?.first?.kind == .onboarding, "create agent with onboarding")
        customAgent.name = "Орбита"
        customAgent.notifications = false
        demo.saveAgent(customAgent)
        check(demo.state.agents.filter { $0.id == "custom" }.count == 1 && demo.state.agents.first { $0.id == "custom" }?.name == "Орбита", "edit agent without duplicating it")
        check(demo.state.agents.first { $0.id == "custom" }?.notifications == false, "save agent notification preference")
        demo.send("/Категоризировать расходы", conversation: "agent:finance", agentID: "finance")
        check(demo.state.threads["agent:finance"]?.last?.kind == .transactions, "run saved skill")

        let connection = MacDemoConnection(id: "test-mcp", pluginID: "composio", label: "Тестовый сервер", account: "demo", endpoint: "https://demo.blot/mcp")
        demo.saveConnection(connection)
        check(demo.state.connections.contains { $0.id == connection.id && $0.endpoint == connection.endpoint }, "save MCP settings locally")
        demo.update { $0.settings.usageLimit = "$25"; $0.settings.profileName = "Демо" }
        let restored = MacDemoSession(repository: repository)
        check(restored.state.threads["agent:chief"]?.count == demo.state.threads["agent:chief"]?.count, "restore full conversation")
        check(restored.state.emails.first { $0.id == "lisa" }?.sent == true, "restore sent status")
        check(restored.state.settings.usageLimit == "$25" && restored.state.settings.profileName == "Демо", "restore preferences")
        check(restored.state.groups.contains { $0.id == group }, "restore multiple groups")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scheduler = MacDemoScheduler(calendar: calendar)
        let formatter = ISO8601DateFormatter()
        let sunday = formatter.date(from: "2026-11-08T08:00:00Z")!
        var routine = MacDemoRoutine(id: "schedule", title: "Проверка", agentID: "chief", instructions: "Проверь почту")
        let monday = formatter.date(from: "2026-11-09T09:00:00Z")!
        check(scheduler.nextRun(routine, after: sunday) == monday, "skip weekend")
        check(scheduler.isDue(routine, at: monday), "scheduled minute is due")
        routine.lastRun = monday
        check(!scheduler.isDue(routine, at: monday.addingTimeInterval(20)), "run at most once per minute")
        routine.enabled = false
        check(scheduler.nextRun(routine, after: sunday) == nil, "paused schedules do not run")
        check(!scheduler.validTime("25:70"), "reject invalid time")

        let documentsBefore = demo.state.documents.count
        demo.send("Подготовь контент-план", conversation: "agent:content", agentID: "content")
        check(demo.state.documents.count == documentsBefore + 1, "create editable document")
        let attachedBefore = demo.state.documents.count
        demo.send("Прочитай документ", conversation: "agent:support", agentID: "support", attachments: ["Регламент поддержки.docx"])
        check(demo.state.documents.count == attachedBefore, "reading an attachment does not create unrelated documents")
        check(demo.state.threads["agent:support"]?.last?.text.contains("Возвраты") == true, "read the selected document contents")
        demo.send("Подготовь контент-план", conversation: "group:editorial", agentID: "chief", groupIDs: ["chief", "content"])
        check(demo.state.threads["group:editorial"]?.contains { $0.kind == .document } == true, "delegate a content task")
        check(demo.state.threads["group:editorial"]?.contains { $0.kind == .invoices } == false, "group results follow the requested task")
        let blockedBefore = demo.state.products.count
        demo.send("Открой сайт в интернете", conversation: "agent:chief", agentID: "chief")
        check(demo.state.threads["agent:chief"]?.last?.text.contains("отключены") == true && demo.state.products.count == blockedBefore, "exclude internet and PC")
        demo.update { $0.settings.usageResetAt = sunday }
        demo.runDueRoutines(now: sunday.addingTimeInterval(60))
        check(demo.state.settings.usedActions == 0, "reset weekly demo usage")
        let settingsData = try JSONEncoder().encode(demo.state.settings)
        var legacy = try JSONSerialization.jsonObject(with: settingsData) as! [String: Any]
        legacy.removeValue(forKey: "usageResetAt")
        let restoredSettings = try JSONDecoder().decode(MacDemoSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(restoredSettings.plan == demo.state.settings.plan, "read existing preferences after adding reset dates")
        let automatic = MacDemoSession(repository: MacDemoFileRepository(url: directory.appendingPathComponent("automatic.json")))
        var automaticRoutine = MacDemoRoutine(id: "auto", title: "Демо-почта", agentID: "inbox", instructions: "Проверь почту", quiet: false, requiresApproval: false)
        automatic.saveRoutine(automaticRoutine)
        automatic.runRoutine("auto")
        check(automatic.state.emails.first { $0.id == "anna" }?.sent == true && automatic.state.emails.first { $0.id == "lisa" }?.sent == true, "demo routine can send after approval requirement is disabled")
        automatic.update { state in
            for index in state.connections.indices { state.connections[index].allowSend = false }
            if let index = state.emails.firstIndex(where: { $0.id == "anna" }) { state.emails[index].sent = false }
        }
        automatic.runRoutine("auto")
        check(automatic.state.emails.first { $0.id == "anna" }?.sent == false, "automatic demo actions still respect account permissions")
        automatic.update { state in for index in state.emails.indices { state.emails[index].sent = true } }
        automaticRoutine.quiet = true
        automatic.saveRoutine(automaticRoutine)
        let quietCount = automatic.state.threads["agent:inbox"]?.count
        automatic.runRoutine("auto")
        check(automatic.state.threads["agent:inbox"]?.count == quietCount, "quiet routine produces no message when there is no news")
        check(demo.checkoutDemoOrder(conversation: "agent:research", agentID: "research") == nil, "cannot checkout an empty demo cart")
        demo.addToCart("tcl")
        demo.addToCart("tcl")
        check(demo.state.cart == ["tcl"], "cart does not duplicate selected products")
        let order = demo.checkoutDemoOrder(conversation: "agent:research", agentID: "research")
        check(demo.state.documents.first { $0.id == order }?.body.contains("$297.99") == true, "demo order preserves its products and total")
        check(demo.state.cart?.isEmpty == true, "checkout clears the local cart")
        check(demo.state.threads["agent:research"]?.last?.referenceID == order, "checkout produces an order document in the conversation")
        demo.send("Сравни саундбары до $300", conversation: "agent:research", agentID: "research")
        check(Double(demo.state.threads["agent:research"]?.last?.referenceID ?? "") == 300, "parse a product budget from the request")
        var legacyWorkspace = try JSONSerialization.jsonObject(with: JSONEncoder().encode(demo.state)) as! [String: Any]
        legacyWorkspace.removeValue(forKey: "cart")
        let priorWorkspace = try JSONDecoder().decode(MacDemoState.self, from: JSONSerialization.data(withJSONObject: legacyWorkspace))
        check(priorWorkspace.cart == nil && priorWorkspace.agents.count == demo.state.agents.count, "load a workspace saved before demo cart support")
        let permissions = MacDemoSession(repository: MacDemoFileRepository(url: directory.appendingPathComponent("permissions.json")))
        var personal = permissions.state.connections.first { $0.id == "gmail-personal" }!
        personal.allowRead = false
        permissions.saveConnection(personal)
        permissions.send("Проверь почту", conversation: "agent:inbox", agentID: "inbox")
        let newlyRead = permissions.state.threads["agent:inbox", default: []].suffix(2)
        check(!newlyRead.contains { $0.referenceID == "lisa" }, "respect read permission for each mailbox")
        permissions.send("Подготовь ответ Лизе", conversation: "agent:inbox", agentID: "inbox")
        check(permissions.state.threads["agent:inbox"]?.last?.kind == .connection, "a different mailbox cannot grant access to Lisa's email")
        var work = permissions.state.connections.first { $0.id == "gmail-work" }!
        work.label = "Работа"
        permissions.saveConnection(work)
        check(permissions.state.emails.first { $0.id == "anna" }?.accountLabel == "Работа", "renaming an account preserves its email association")
        check(permissions.canSendEmail("anna"), "renamed account keeps its permissions")
        permissions.update { state in state.connections.removeAll { $0.pluginID == "quickbooks" } }
        permissions.send("Проверь расходы", conversation: "agent:finance", agentID: "finance")
        check(permissions.state.threads["agent:finance"]?.last?.referenceID == "quickbooks", "disconnected tools request a new demo connection")

        let corrupted = directory.appendingPathComponent("corrupt.json")
        try Data("invalid".utf8).write(to: corrupted)
        let recovery = MacDemoSession(repository: MacDemoFileRepository(url: corrupted))
        recovery.send("Проверка", conversation: "agent:chief", agentID: "chief")
        check(recovery.persistenceError != nil, "report persistence errors")
        let preserved = try String(contentsOf: corrupted, encoding: .utf8)
        check(preserved == "invalid", "do not overwrite unreadable user data")
        try verifyConversationInteractions(directory: directory)
        print("Passed \(checks) macOS demo checks")
    }
    static func verifyConversationInteractions(directory: URL) throws {
        let repository = MacDemoFileRepository(url: directory.appendingPathComponent("interactions.json"))
        let demo = MacDemoSession(repository: repository)
        let key = "group:orders"
        let originalCount = demo.state.threads[key]!.count
        demo.prepareCollaboration(in: "orders")
        let examples = Array(demo.state.threads[key]!.dropFirst(originalCount))
        check(examples.first?.isUser == true, "collaboration includes an outgoing message")
        check(examples.filter { !$0.isUser }.count == 4, "collaboration includes all three group agents")
        check(examples.contains { $0.text.contains("@{finance}") && $0.text.contains("@{inbox}") }, "agents address teammates by stable IDs")
        check(examples.contains { $0.reactions?.count == 2 }, "agents can react to the same message")
        let ids = Set(demo.state.threads[key]!.map(\.id))
        check(examples.compactMap(\.replyToID).allSatisfy { ids.contains($0) }, "every quote references an existing message")
        let count = demo.state.threads[key]!.count
        demo.prepareCollaboration(in: "orders")
        check(demo.state.threads[key]!.count == count, "reopening a group does not duplicate the example")
        check(demo.state.threads[key]!.prefix(originalCount).count == originalCount, "collaboration preserves existing history")

        let target = examples[1]
        demo.toggleReaction("❤️", messageID: target.id, conversation: key)
        check(demo.state.threads[key]!.first { $0.id == target.id }?.reactions?.count == 3, "user reaction preserves agent reactions")
        demo.toggleReaction("🔥", messageID: target.id, conversation: key)
        let mine = demo.state.threads[key]!.first { $0.id == target.id }!.reactions!.filter { $0.authorID == MacDemoReaction.userID }
        check(mine.count == 1 && mine[0].emoji == "🔥", "changing a reaction keeps one reaction per participant")
        demo.toggleReaction("🔥", messageID: target.id, conversation: key)
        check(demo.state.threads[key]!.first { $0.id == target.id }?.reactions?.count == 2, "tapping the selected reaction removes only your reaction")
        demo.toggleReaction("invalid", messageID: target.id, conversation: key)
        demo.toggleReaction("👍", messageID: target.id, conversation: key, authorID: "missing")
        check(demo.state.threads[key]!.first { $0.id == target.id }?.reactions?.count == 2, "reject unsupported reactions and unknown participants")
        let own = examples[0]
        demo.toggleReaction("👀", messageID: own.id, conversation: key)
        check(demo.state.threads[key]!.first { $0.id == own.id }?.reactions?.first?.emoji == "👀", "user can react to their own message")
        demo.send("Ответ на своё сообщение", conversation: key, agentID: "chief", replyToID: own.id)
        let reply = demo.state.threads[key]!.first { $0.isUser && $0.text == "Ответ на своё сообщение" }!
        check(reply.replyToID == own.id, "reply to an outgoing message")
        check(demo.state.threads[key]!.last?.replyToID == reply.id, "agent acknowledges a quoted user reply")
        demo.send("Ответ агенту", conversation: key, agentID: "chief", replyToID: target.id)
        check(demo.state.threads[key]!.first { $0.text == "Ответ агенту" }?.replyToID == target.id, "reply to an incoming message")
        demo.send("Другая переписка", conversation: "agent:chief", agentID: "chief", replyToID: own.id)
        check(demo.state.threads["agent:chief"]!.first { $0.text == "Другая переписка" }?.replyToID == nil, "reject cross-conversation quote IDs")
        let restored = MacDemoSession(repository: repository)
        check(restored.state.threads[key]!.first { $0.id == own.id }?.reactions?.first?.emoji == "👀", "persist reactions across launches")
        check(restored.state.threads[key]!.first { $0.id == reply.id }?.replyToID == own.id, "persist reply links across launches")

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as! [String: Any]
        legacy.removeValue(forKey: "reactions")
        legacy.removeValue(forKey: "replyToID")
        let decoded = try JSONDecoder().decode(MacDemoMessage.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(decoded.reactions == nil && decoded.replyToID == nil && decoded.text == target.text, "load messages saved before reactions and replies")
        check(MacDemoMessageText.segments("Привет, @{chief}!") == [.text("Привет, "), .agent("chief"), .text("!")], "parse inline mentions without losing punctuation")
        check(MacDemoMessageText.segments("текст @{без конца") == [.text("текст @{без конца")], "preserve incomplete mention text")
        var agent = demo.state.agents[0]
        agent.name = "Новое имя"
        check(MacDemoMessageText.plain("@{chief}", agents: [agent]) == "@Новое имя", "mentions follow a renamed agent")
        check(MacDemoMessageText.plain("@{missing}", agents: []) == "@Удалённый агент", "missing mention has a readable fallback")
    }

}
