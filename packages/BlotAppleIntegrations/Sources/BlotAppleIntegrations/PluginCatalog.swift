import Foundation

public enum ApplePluginID: String, Codable, CaseIterable, Sendable {
    case mail = "apple.mail", calendar = "apple.calendar", reminders = "apple.reminders"
    case notes = "apple.notes", contacts = "apple.contacts", files = "apple.files", shortcuts = "apple.shortcuts"

    public var name: String {
        switch self {
        case .mail: "Почта"
        case .calendar: "Календарь"
        case .reminders: "Напоминания"
        case .notes: "Заметки"
        case .contacts: "Контакты"
        case .files:
            #if os(macOS)
            "Finder"
            #else
            "Файлы"
            #endif
        case .shortcuts: "Команды"
        }
    }
    public var bundleID: String {
        switch self {
        case .mail:
            #if os(macOS)
            "com.apple.mail"
            #else
            "com.apple.mobilemail"
            #endif
        case .calendar:
            #if os(macOS)
            "com.apple.iCal"
            #else
            "com.apple.mobilecal"
            #endif
        case .reminders: "com.apple.reminders"
        case .notes:
            #if os(macOS)
            "com.apple.Notes"
            #else
            "com.apple.mobilenotes"
            #endif
        case .contacts:
            #if os(macOS)
            "com.apple.AddressBook"
            #else
            "com.apple.MobileAddressBook"
            #endif
        case .files:
            #if os(macOS)
            "com.apple.finder"
            #else
            "com.apple.DocumentsApp"
            #endif
        case .shortcuts: "com.apple.shortcuts"
        }
    }
    public var available: Bool {
        #if os(iOS)
        self != .notes
        #else
        true
        #endif
    }
    public var summary: String {
        switch self {
        case .calendar: "События и встречи в выбранных календарях."
        case .reminders: "Задачи и сроки в выбранных списках."
        case .contacts: "Поиск, создание и изменение доступных контактов."
        case .files: "Работа с файлами в выбранных вами папках."
        case .shortcuts: "Запуск выбранных команд. Команда может запросить дополнительные разрешения."
        case .notes:
            #if os(iOS)
            "Доступно на Mac. Чтение и изменение заметок на iPhone пока не поддерживаются."
            #else
            "Поиск, чтение и изменение текста заметок в выбранных папках. Заблокированные заметки недоступны."
            #endif
        case .mail:
            #if os(iOS)
            "Подготовка письма в системном редакторе. Отправляете вы. Чтение ящика недоступно в этой интеграции."
            #else
            "Поиск и чтение писем, черновики, ответы и отправка из выбранных аккаунтов."
            #endif
        }
    }
    public var asset: String { "PluginApple" + rawValue.dropFirst(6).capitalized }
}

public struct PluginCatalogEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let asset: String
    public let category: String
    public let scopes: [String]
    public var appleID: ApplePluginID? { ApplePluginID(rawValue: id) }
}

public enum PluginCatalog {
    public static let apple = ApplePluginID.allCases.map {
        PluginCatalogEntry(id: $0.rawValue, name: $0.name, summary: $0.summary, asset: $0.asset,
            category: "Приложения Apple", scopes: ["read", "create", "update"])
    }
    public static let external: [PluginCatalogEntry] = [
        entry("gmail", "Gmail", "Поиск, чтение и подготовка писем.", "PluginGmail", "Общение", ["mail.read", "mail.draft"]),
        entry("calendar", "Google Calendar", "Встречи, события и расписание.", "PluginCalendar", "Работа", ["calendar.read", "calendar.write"]),
        entry("drive", "Google Drive", "Документы и файлы вашей команды.", "PluginDrive", "Работа", ["files.read", "files.write"]),
        entry("slack", "Slack", "Каналы, сообщения и контекст команды.", "PluginSlack", "Общение"),
        entry("notion", "Notion", "Заметки, базы данных и проекты.", "PluginNotion", "Работа"),
        entry("quickbooks", "QuickBooks", "Операции, счета и финансовые отчёты.", "PluginQuickBooks", "Финансы"),
        entry("freshdesk", "Freshdesk", "Обращения клиентов и ответы поддержки.", "PluginFreshdesk", "Общение"),
        entry("1password", "1Password", "Выделенное хранилище для агентов.", "Plugin1Password", "Пароли", ["vault.read"]),
        entry("composio", "Composio", "Подключение инструментов через MCP.", "PluginComposio", "MCP"),
        entry("zapier", "Zapier", "Ваши приложения и рабочие процессы.", "PluginZapier", "MCP"),
        entry("github", "GitHub", "Репозитории, задачи и проверка изменений.", "PluginGitHub", "Разработка"),
        entry("beehiiv", "Beehiiv", "Рассылки, статьи и черновики.", "PluginBeehiiv", "Контент"),
        entry("granola", "Granola", "Контекст встреч и заметки команды.", "PluginGranola", "Работа", ["notes.read"]),
        entry("airtable", "Airtable", "Таблицы, базы и рабочие процессы.", "PluginAirtable", "Работа"),
        entry("asana", "Asana", "Задачи и статусы проектов.", "PluginAsana", "Работа"),
        entry("adobe", "Adobe Developer App Builder", "Инструменты разработки и тестирования.", "PluginAdobe", "Разработка"),
        entry("atlassian", "Atlassian Forge", "Проекты, задачи и приложения команды.", "PluginAtlassian", "Разработка"),
        entry("loom", "Loom", "Видеозаписи и обновления команды.", "PluginLoom", "Общение", ["videos.read", "videos.create"])
    ]
    public static var all: [PluginCatalogEntry] { apple + external }
    private static func entry(_ id: String, _ name: String, _ summary: String, _ asset: String, _ category: String,
                              _ scopes: [String] = []) -> PluginCatalogEntry {
        .init(id: id, name: name, summary: summary, asset: asset, category: category, scopes: scopes)
    }
}

public struct AppleResource: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum AppleIntegrationError: Error, LocalizedError, Sendable {
    case permissionDenied, unavailable, invalidArguments, missingResource, uncertainResult, canceled
    case system(String)
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Нужно разрешение или подключение для этого агента."
        case .unavailable: "Это действие недоступно на данном устройстве."
        case .invalidArguments: "Проверьте параметры действия."
        case .missingResource: "Объект недоступен в выбранных ресурсах."
        case .uncertainResult: "Исход действия неизвестен. Проверьте системное приложение и отметьте результат в карточке подключения перед повтором."
        case .canceled: "Действие отменено."
        case .system(let message): message
        }
    }
}
