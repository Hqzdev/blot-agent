import BlotWorkspace

/// Presents the same prepared values in user-facing language without exposing tool schemas.
enum AppleActionReview {
    static func title(_ tool: AppleTool) -> String {
        let actions = ["create": "Создать", "update": "Изменить", "delete": "Удалить", "send": "Отправить",
                       "move": "Переместить", "run": "Запустить команду", "reply": "Подготовить ответ"]
        return tool.plugin.name + " · " + (actions[tool.operation] ?? tool.operation)
    }
    static func details(arguments: ChatJSON, preview: ChatJSON?, resourceName: String) -> String {
        var sections = ["Ресурс: " + resourceName]
        let parameters = fields(arguments)
        if !parameters.isEmpty { sections.append(parameters) }
        if let preview {
            let current = fields(preview)
            if !current.isEmpty { sections.append("Текущий объект:\n" + current) }
        }
        return sections.joined(separator: "\n\n")
    }
    private static func fields(_ json: ChatJSON) -> String {
        guard case .object(let values) = json else { return "" }
        let labels = [("title", "Название"), ("name", "Имя"), ("subject", "Тема"), ("sender", "Отправитель"),
            ("recipient", "Получатель"), ("start", "Начало"), ("end", "Окончание"), ("due", "Срок"), ("completed", "Завершено"),
            ("location", "Место"), ("given_name", "Имя"), ("family_name", "Фамилия"), ("email", "Электронная почта"),
            ("phone", "Телефон"), ("path", "Файл"), ("destination", "Назначение"), ("size", "Размер"),
            ("modified", "Изменён"), ("input", "Вход команды"), ("notes", "Заметки"), ("body", "Текст"), ("content", "Содержимое")]
        return labels.compactMap { key, label in
            guard case .string(let value) = values[key], !value.isEmpty else { return nil }
            let display = value == "true" ? "Да" : value == "false" ? "Нет" : value
            return label + ": " + display
        }.joined(separator: "\n\n")
    }
}
