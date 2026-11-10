import BlotAppleIntegrations
import BlotWorkspace
import Foundation

enum WorkspaceSkillToolCatalog {
    /// Native operations require a resource discovery turn in the same task.
    static func includingDiscovery(_ ids: [String]) -> [String] {
        var result = Set(ids)
        for tool in AppleToolCatalog.all where result.contains(tool.definition.name) {
            if let discovery = AppleToolCatalog.tools(for: tool.plugin).first(where: { $0.operation == "resources" }) {
                result.insert(discovery.definition.name)
            }
        }
        return result.sorted()
    }
    static func title(_ id: String, russian: Bool) -> String {
        let local = ["file_read": russian ? "Чтение вложений" : "Read attachments", "document_create": russian ? "Создание документов" : "Create documents",
                     "memory_candidate": russian ? "Предложение памяти" : "Suggest memory"]
        if let title = local[id] { return title }
        guard let tool = AppleToolCatalog.all.first(where: { $0.definition.name == id }) else { return id }
        let operations = russian ? ["resources": "Доступные ресурсы", "list": "Список", "read": "Чтение", "search": "Поиск", "create": "Создание", "update": "Изменение", "delete": "Удаление", "send": "Отправка", "reply": "Ответ", "move": "Перемещение", "run": "Запуск"] :
            ["resources": "Available resources", "list": "List", "read": "Read", "search": "Search", "create": "Create", "update": "Update", "delete": "Delete", "send": "Send", "reply": "Reply", "move": "Move", "run": "Run"]
        return tool.plugin.name + " · " + (operations[tool.operation] ?? tool.operation)
    }
}
