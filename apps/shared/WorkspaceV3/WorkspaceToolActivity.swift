import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

struct WorkspaceToolActivity: Identifiable {
    enum State { case queued, running, waitingForAnswer, approval, succeeded, failed, denied, stopped, unknown }
    struct Detail { let label: String; let value: String }
    let id: String
    let tool: String
    let state: State
    let symbol: String
    let plugin: WorkspacePluginReference?
    let provider: String?
    let verb: (ru: String, en: String)
    let details: [Detail]
    let logArtifactID: UUID?
    func title(russian: Bool) -> String { russian ? verb.ru : verb.en }
    func status(russian: Bool) -> String {
        switch state {
        case .queued: return russian ? "Ожидает" : "Queued"
        case .running: return russian ? "В работе" : "Running"
        case .waitingForAnswer: return russian ? "Ожидает вашего ответа" : "Waiting for your answer"
        case .approval: return russian ? "Нужно разрешение" : "Needs approval"
        case .succeeded: return russian ? "Готово" : "Done"
        case .failed: return russian ? "Ошибка" : "Failed"
        case .denied: return russian ? "Не разрешено" : "Denied"
        case .stopped: return russian ? "Остановлено" : "Stopped"
        case .unknown: return russian ? "Нужна сверка" : "Check outcome"
        }
    }
}

/// Uses only explicit calls/results, not model prose or prior requests embedded in requestJSON.
struct WorkspaceToolActivityBuilder {
    private static let titles: [String: (String, String, String, String, String)] = [
            "drive_create": ("doc", "Сохраняет файл в Drive", "Сохранил файл в Drive", "Saving file to Drive", "Saved file to Drive"),
            "google_accounts": ("person.crop.circle", "Проверяет аккаунты Google", "Проверил аккаунты Google", "Checking Google accounts", "Checked Google accounts"),
            "gmail_check_access": ("envelope", "Проверяет доступ к Gmail", "Проверил доступ к Gmail", "Checking Gmail access", "Checked Gmail access"),
            "gmail_recent": ("tray", "Смотрит последние письма в Gmail", "Проверил последние письма в Gmail", "Checking recent Gmail messages", "Checked recent Gmail messages"),
            "skill_list": ("shippingbox", "Ищет навыки", "Проверил навыки", "Finding skills", "Checked skills"),
            "skill_read": ("shippingbox", "Читает навык", "Прочитал навык", "Reading skill", "Read skill"),
            "skill_create": ("sparkle", "Создаёт навык", "Сохранил навык", "Creating skill", "Saved skill"),
            "skill_run": ("shippingbox", "Запускает навык", "Поставил навык в очередь", "Starting skill", "Queued skill"),
            "plugin_catalog": ("puzzlepiece.extension", "Проверяет приложения", "Проверил приложения", "Checking apps", "Checked apps"),
            "plugin_connect": ("powerplug", "Ожидает подключения", "Подтвердил подключение", "Waiting for connection", "Verified connection"),
            "conversation_ask": ("questionmark.circle", "Уточняет детали", "Получил ответ", "Asking for details", "Received answer"),
            "subscription_plans": ("creditcard", "Открывает тарифы", "Показал тарифы", "Opening plans", "Showed plans"),
            "connection_status": ("puzzlepiece.extension", "Проверяет подключение", "Проверил подключение", "Checking connection", "Checked connection"),
            "secure_input_request": ("lock", "Ожидает защищённый ввод", "Завершил защищённый ввод", "Waiting for secure input", "Finished secure input"),
            "browser_request_takeover": ("hand.raised", "Ожидает ручной шаг", "Получил управление", "Waiting for manual step", "Returned control"),
            "browser_profiles": ("person.crop.circle", "Смотрит профили Ori", "Посмотрел профили Ori", "Inspecting Ori profiles", "Inspected Ori profiles"),
            "browser_copy_cookies": ("globe", "Переносит вход", "Перенёс вход", "Transferring sign-in", "Transferred sign-in"),
            "browser_tabs": ("globe", "Смотрит открытые вкладки", "Посмотрел открытые вкладки", "Inspecting open tabs", "Inspected open tabs"),
            "browser_open": ("globe", "Открывает сайт", "Открыл сайт", "Opening website", "Opened website"),
            "browser_snapshot": ("globe", "Читает страницу", "Прочитал страницу", "Reading page", "Read page"),
            "browser_attach": ("cursorarrow", "Запрашивает управление вкладкой", "Подключился к вкладке", "Requesting tab control", "Attached to tab"),
            "browser_click": ("cursorarrow.click", "Нажимает на странице", "Нажал на странице", "Clicking on page", "Clicked on page"),
            "browser_type": ("keyboard", "Заполняет поле", "Заполнил поле", "Filling field", "Filled field"),
            "browser_scroll": ("arrow.up.and.down", "Прокручивает страницу", "Прокрутил страницу", "Scrolling page", "Scrolled page"),
            "browser_back": ("arrow.left", "Возвращается на предыдущую страницу", "Вернулся на предыдущую страницу", "Going back", "Went back"),
            "browser_close": ("xmark", "Закрывает вкладку", "Закрыл вкладку", "Closing tab", "Closed tab"),
            "browser_purchase": ("cart", "Подтверждает заказ на сайте", "Нажал кнопку оформления заказа", "Confirming website order", "Clicked the order button"),
            "browser_screenshot": ("photo", "Сохраняет снимок страницы", "Сохранил снимок страницы", "Saving page image", "Saved page image"),
            "process_run": ("terminal", "Выполняет команду", "Выполнил команду", "Running command", "Ran command"),
            "process_status": ("terminal", "Проверяет команду", "Проверил команду", "Checking command", "Checked command"),
            "process_stop": ("stop.circle", "Останавливает команду", "Остановил команду", "Stopping command", "Stopped command"),
            "document_create": ("doc", "Создаёт документ", "Создал документ", "Creating document", "Created document"),
            "file_read": ("doc.text", "Читает файл", "Прочитал файл", "Reading file", "Read file"),
            "workspace_directory": ("folder", "Открывает рабочую папку", "Открыл рабочую папку", "Opening workspace folder", "Opened workspace folder"),
            "workspace_read_file": ("doc.text", "Читает файл", "Прочитал файл", "Reading file", "Read file"),
            "project_read_file": ("doc.text", "Читает файл", "Прочитал файл", "Reading file", "Read file"),
            "project_search": ("magnifyingglass", "Ищет в проекте", "Проверил файлы проекта", "Searching project", "Searched project"),
            "workspace_list_files": ("folder", "Просматривает файлы", "Просмотрел файлы", "Listing files", "Listed files"),
            "workspace_write_file": ("doc.badge.plus", "Сохраняет файл", "Сохранил файл", "Saving file", "Saved file"),
            "project_write_file": ("doc.badge.plus", "Изменяет файл", "Изменил файл", "Editing file", "Edited file"),
            "workspace_create_directory": ("folder.badge.plus", "Создаёт папку", "Создал папку", "Creating folder", "Created folder"),
            "workspace_request_directory": ("folder", "Запрашивает доступ к папке", "Получил доступ к папке", "Requesting folder access", "Obtained folder access"),
            "git_status": ("arrow.triangle.branch", "Проверяет Git", "Проверил Git", "Checking Git", "Checked Git"),
            "git_diff": ("arrow.triangle.branch", "Смотрит изменения", "Посмотрел изменения", "Inspecting changes", "Inspected changes"),
            "git_commit": ("arrow.triangle.branch", "Создаёт коммит", "Создал коммит", "Creating commit", "Created commit"),
            "git_push": ("arrow.up", "Отправляет коммит", "Отправил коммит", "Pushing commit", "Pushed commit")
        ]
    private typealias State = WorkspaceToolActivity.State
    struct Result { var rows: [WorkspaceToolActivity]; let dependencies: Set<UUID> }
    func build(steps: [BlotV3.ModelStep], actions: [UUID: BlotV3.PreparedAction], invocations: [UUID: BlotV3.ToolInvocation],
               connections: [BlotV3.McpConnection], pendingQuestionIDs: Set<UUID> = []) -> Result {
        var rows: [WorkspaceToolActivity] = [], dependencies: Set<UUID> = []
        var positions: [String: Int] = [:]
        for step in steps.sorted(by: { $0.stepIndex < $1.stepIndex }) {
            guard let calls: [ChatToolCall] = decode(step.toolCallsJSON) else { continue }
            let results: [String: ChatJSON] = decode(step.toolResultsJSON) ?? [:]
            var awaiting = false
            for call in calls {
                let ids = actionIDs(step, call: call); dependencies.formUnion(ids)
                let action = ids.compactMap { actions[$0] }.first { $0.toolId == call.name }
                let invocation = action.flatMap { invocations[$0.metadata.id] }
                let result = invocation?.result.flatMap { decode($0) as ChatJSON? } ?? results[call.id]
                let executionState = state(step: step, result: result, action: action, invocation: invocation, queued: awaiting)
                let waitingForAnswer = executionState == .running && result == nil && call.name == "conversation_ask"
                    && ids.first.map(pendingQuestionIDs.contains) == true
                let state: State = waitingForAnswer ? .waitingForAnswer : executionState
                if results[call.id] == nil { awaiting = true }
                let plugin = WorkspacePluginReference.plugin(forTool: call.name)
                    ?? connections.first { $0.toolIds.contains(call.name) }.flatMap { connection in
                        PluginCatalog.all.first { $0.name.caseInsensitiveCompare(connection.name) == .orderedSame }
                            .map { WorkspacePluginReference(entry: $0, name: $0.name) }
                    }
                let provider = plugin?.name ?? connections.first { $0.toolIds.contains(call.name) }?.name
                let presentation = presentation(call.name, state: state)
                let detail = details(call, result: result)
                let processID = fields(call.arguments)["process_id"].flatMap(string)
                let key = call.name == "process_status" ? "process-status:" + (processID ?? call.id) : step.metadata.id.uuidString + ":" + call.id
                let row = WorkspaceToolActivity(id: key, tool: call.name, state: state, symbol: presentation.symbol, plugin: plugin,
                    provider: provider, verb: presentation.verb, details: detail,
                    logArtifactID: fields(result)["log_artifact_id"].flatMap(string).flatMap(UUID.init(uuidString:)))
                if let index = positions[key] { rows[index] = row }
                else { positions[key] = rows.count; rows.append(row) }
            }
        }
        return Result(rows: Array(rows.suffix(64)), dependencies: dependencies)
    }
    private func actionIDs(_ step: BlotV3.ModelStep, call: ChatToolCall) -> [UUID] {
        guard let workspace = step.metadata.workspaceId else { return [] }
        return [WorkspaceToolCallIdentity.actionID(workspaceID: workspace, sourceID: step.sourceMessageId, callID: call.id),
                WorkspaceToolCallIdentity.actionID(workspaceID: workspace, sourceID: step.sourceMessageId, callID: call.id, scope: .browser),
                WorkspaceToolCallIdentity.actionID(workspaceID: workspace, sourceID: step.sourceMessageId, callID: call.id, scope: .sessionFile)]
    }
    private func state(step: BlotV3.ModelStep, result: ChatJSON?, action: BlotV3.PreparedAction?, invocation: BlotV3.ToolInvocation?, queued: Bool) -> State {
        switch invocation?.state ?? action?.state {
        case .unknown: return .unknown
        case .denied, .expired: return .denied
        case .failed: return .failed
        case .running: return .running
        case .succeeded: break
        case .prepared, .waiting_approval: return .approval
        default: break
        }
        if let result {
            let values = fields(result)
            if let processState = values["process_state"].flatMap(string)?.lowercased(), ["canceled", "cancelled", "stopped"].contains(processState) { return .stopped }
            if case .number(let code) = values["exitCode"], code != 0 { return .failed }
            switch values["state"].flatMap(string)?.lowercased() {
            case "unknown": return .unknown
            case "queued": return values["task_id"] == nil ? .queued : .succeeded
            case "running", "pending": return .running
            case "canceled", "cancelled", "stopped", "dismissed": return .stopped
            case "not_connected", "unavailable": return .failed
            case "denied", "expired": return .denied
            default: break
            }
            if values["isError"] == .bool(true) || WorkspaceGroupExecutionEvidence.containsFailure(result) { return .failed }
            return .succeeded
        }
        if invocation?.state == .succeeded || action?.state == .succeeded { return .succeeded }
        switch step.state {
        case .canceled: return .stopped
        case .interrupted: return .unknown
        case .failed: return .failed
        case .completed: return .unknown
        default: return queued ? .queued : .running
        }
    }
    private func presentation(_ tool: String, state: State) -> (symbol: String, verb: (ru: String, en: String)) {
        let done = state == .succeeded
        if state != .running && state != .waitingForAnswer && !done {
            if tool.hasPrefix("browser_"), let entry = Self.titles[tool] { return (entry.0, (entry.1, entry.3)) }
            if tool.hasPrefix("process_") { return ("terminal", ("Команда", "Command")) }
            if tool.hasPrefix("git_") { return ("arrow.triangle.branch", ("Действие Git", "Git action")) }
            if tool.hasPrefix("workspace_") || tool.hasPrefix("project_") || tool == "file_read" || tool == "document_create" { return ("doc.text", ("Работа с файлами", "File operation")) }
            return ("puzzlepiece.extension", ("Действие инструмента", "Tool action"))
        }

        if let entry = Self.titles[tool] { return (entry.0, (done ? entry.2 : entry.1, done ? entry.4 : entry.3)) }
        if let apple = AppleToolCatalog.all.first(where: { $0.definition.name == tool }) {
            let nouns: [ApplePluginID: (String, String)] = [.mail: ("письмо", "email"), .calendar: ("событие", "event"), .reminders: ("напоминание", "reminder"), .notes: ("заметку", "note"), .contacts: ("контакт", "contact"), .files: ("файл", "file"), .shortcuts: ("команду", "shortcut")]
            let noun = nouns[apple.plugin] ?? ("запись", "item")
            let verbs: [String: (String, String, String, String)] = [
                "create": ("Создаёт " + noun.0, "Создал " + noun.0, "Creating " + noun.1, "Created " + noun.1),
                "update": ("Изменяет " + noun.0, "Изменил " + noun.0, "Updating " + noun.1, "Updated " + noun.1),
                "delete": ("Удаляет " + noun.0, "Удалил " + noun.0, "Deleting " + noun.1, "Deleted " + noun.1),
                "send": ("Отправляет письмо", "Отправил письмо", "Sending email", "Sent email"),
                "run": ("Запускает команду", "Запустил команду", "Running shortcut", "Ran shortcut")]
            let entry = verbs[apple.operation] ?? ("Читает данные", "Прочитал данные", "Reading data", "Read data")
            return ("app.connected.to.app.below.fill", (done ? entry.1 : entry.0, done ? entry.3 : entry.2))
        }
        if tool.hasPrefix("browser_") { return ("globe", (done ? "Действие браузера выполнено" : "Работает в браузере", done ? "Browser action completed" : "Using browser")) }
        if tool.hasPrefix("git_") { return ("arrow.triangle.branch", (done ? "Действие Git выполнено" : "Работает с Git", done ? "Git action completed" : "Using Git")) }
        return ("puzzlepiece.extension", (done ? "Вызов инструмента завершён" : "Использует инструмент", done ? "Tool call completed" : "Using tool"))
    }
    private func details(_ call: ChatToolCall, result: ChatJSON?) -> [WorkspaceToolActivity.Detail] {
        let arguments = fields(call.arguments), output = fields(result)
        var items: [WorkspaceToolActivity.Detail] = []
        if output["error"] == .string("invalid_arguments") {
            items.append(.init(label: "Запрос / Request", value: "Не выполнен: агент должен исправить параметры. / Not executed: the agent must correct its arguments."))
        }
        var truncated = false
        if let path = arguments["path"].flatMap(string) { items.append(.init(label: "Файл / File", value: clean(path, maximum: 240))) }
        if let url = (arguments["url"] ?? output["url"]).flatMap(string).flatMap(URL.init(string:)), let host = url.host { items.append(.init(label: "Сайт / Site", value: clean(host))) }
        if call.name.hasPrefix("browser_"), let error = output["error"].flatMap(string), error != "invalid_arguments" {
            items.append(.init(label: "Ошибка / Error", value: clean(error)))
        }
        if let executable = arguments["executable"].flatMap(string) { items.append(.init(label: "Программа / Program", value: (executable as NSString).lastPathComponent)) }
        // Never echo arbitrary parameters, page text, environment variables or opaque plugin output.
        for (key, title) in [("title", "Название / Title"), ("name", "Название / Name"), ("exitCode", "Код выхода / Exit code"), ("stdout", "stdout"), ("stderr", "stderr")] {
            guard let value = output[key] else { continue }
            let text: String
            if let value = string(value) { text = value }
            else if case .number(let value) = value { text = String(value) }
            else { continue }
            truncated = truncated || text.count > 3000
            if !text.isEmpty { items.append(.init(label: title, value: clean(text, maximum: 3000))) }
        }
        if output["truncated"] == .bool(true) || truncated { items.append(.init(label: "Журнал / Log", value: "Показан фрагмент / Output truncated")) }
        return items
    }
    private func clean(_ value: String, maximum: Int = 160) -> String {
        String(String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }).prefix(maximum))
    }
    private func fields(_ value: ChatJSON?) -> [String: ChatJSON] { if case .object(let values) = value { return values }; return [:] }
    private func string(_ value: ChatJSON) -> String? { if case .string(let text) = value { return text }; return nil }
    private func decode<T: Decodable>(_ raw: String?) -> T? {
        guard let raw, raw.utf8.count <= 4_194_304 else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(raw.utf8))
    }
}
