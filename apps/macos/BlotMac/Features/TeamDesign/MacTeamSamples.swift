enum MacTeamSamples {
    static let plugins: [MacTeamPlugin] = [
        .init(
            id: "gmail", name: "Gmail", assetName: "PluginGmail", category: "Общение",
            summary: "Поиск, чтение и подготовка писем."),
        .init(
            id: "calendar", name: "Google Calendar", assetName: "PluginCalendar", category: "Работа",
            summary: "Встречи, события и расписание."),
        .init(
            id: "drive", name: "Google Drive", assetName: "PluginDrive", category: "Работа",
            summary: "Документы и файлы вашей команды."),
        .init(
            id: "slack", name: "Slack", assetName: "PluginSlack", category: "Общение",
            summary: "Каналы, сообщения и контекст команды."),
        .init(
            id: "notion", name: "Notion", assetName: "PluginNotion", category: "Работа",
            summary: "Заметки, базы данных и проекты."),
        .init(
            id: "quickbooks", name: "QuickBooks", assetName: "PluginQuickBooks", category: "Финансы",
            summary: "Операции, счета и финансовые отчёты."),
        .init(
            id: "freshdesk", name: "Freshdesk", assetName: "PluginFreshdesk",
            category: "Общение", summary: "Обращения клиентов и ответы поддержки."),
        .init(
            id: "1password", name: "1Password", assetName: "Plugin1Password", category: "Пароли",
            summary: "Вход в приложения из отдельного хранилища."),
        .init(
            id: "composio", name: "Composio", assetName: "PluginComposio",
            category: "MCP", summary: "Подключение инструментов через MCP."),
        .init(
            id: "zapier", name: "Zapier", assetName: "PluginZapier", category: "MCP",
            summary: "Ваши приложения и рабочие процессы."),
        .init(
            id: "github", name: "GitHub", assetName: "PluginGitHub",
            category: "Разработка", summary: "Репозитории, задачи и проверка изменений."),
        .init(
            id: "beehiiv", name: "Beehiiv", assetName: "PluginBeehiiv", category: "Контент",
            summary: "Рассылки, статьи и черновики."),
        .init(
            id: "granola", name: "Granola", assetName: "PluginGranola", category: "Работа",
            summary: "Контекст встреч и заметки команды."),
        .init(
            id: "airtable", name: "Airtable", assetName: "PluginAirtable", category: "Работа",
            summary: "Таблицы, базы и рабочие процессы."),
        .init(
            id: "asana", name: "Asana", assetName: "PluginAsana", category: "Работа",
            summary: "Задачи и статусы проектов."),
        .init(
            id: "adobe", name: "Adobe Developer App Builder", assetName: "PluginAdobe", category: "Разработка",
            summary: "Инструменты разработки и тестирования."),
        .init(
            id: "atlassian", name: "Atlassian Forge", assetName: "PluginAtlassian", category: "Разработка",
            summary: "Проекты, задачи и приложения команды."),
    ]
}
