import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

struct WorkspaceToolActivity: Identifiable {
    enum State { case queued, running, approval, succeeded, failed, denied, stopped, unknown }
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
    private typealias State = WorkspaceToolActivity.State
    struct Result { var rows: [WorkspaceToolActivity]; let dependencies: Set<UUID> }
    func build(steps: [BlotV3.ModelStep], actions: [UUID: BlotV3.PreparedAction], invocations: [UUID: BlotV3.ToolInvocation],
               connections: [BlotV3.McpConnection]) -> Result {
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
                let state = state(step: step, result: result, action: action, invocation: invocation, queued: awaiting)
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
            case "running", "queued", "pending": return .running
            case "canceled", "cancelled", "stopped": return .stopped
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
        if state != .running && !done {
            if tool.hasPrefix("browser_") { return ("globe", ("Действие браузера", "Browser action")) }
            if tool.hasPrefix("process_") { return ("terminal", ("Команда", "Command")) }
            if tool.hasPrefix("git_") { return ("arrow.triangle.branch", ("Действие Git", "Git action")) }
            if tool.hasPrefix("workspace_") || tool.hasPrefix("project_") || tool == "file_read" || tool == "document_create" { return ("doc.text", ("Работа с файлами", "File operation")) }
            return ("puzzlepiece.extension", ("Действие инструмента", "Tool action"))
        }
        let entries: [String: (String, String, String, String, String)] = [
            "browser_tabs": ("globe", "Смотрит открытые вкладки", "Посмотрел открытые вкладки", "Inspecting open tabs", "Inspected open tabs"),
            "browser_open": ("globe", "Открывает сайт", "Открыл сайт", "Opening website", "Opened website"),
            "browser_snapshot": ("globe", "Читает страницу", "Прочитал страницу", "Reading page", "Read page"),
            "browser_click": ("cursorarrow.click", "Нажимает на странице", "Нажал на странице", "Clicking on page", "Clicked on page"),
            "browser_type": ("keyboard", "Заполняет поле", "Заполнил поле", "Filling field", "Filled field"),
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
        if let entry = entries[tool] { return (entry.0, (done ? entry.2 : entry.1, done ? entry.4 : entry.3)) }
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
        var truncated = false
        if let path = arguments["path"].flatMap(string) { items.append(.init(label: "Файл / File", value: clean(path, maximum: 240))) }
        if let url = arguments["url"].flatMap(string).flatMap(URL.init(string:)), let host = url.host { items.append(.init(label: "Сайт / Site", value: clean(host))) }
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
