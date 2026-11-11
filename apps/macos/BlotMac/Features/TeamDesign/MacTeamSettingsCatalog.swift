import BlotDesign
import Foundation

enum MacTeamSettingsPane: String, CaseIterable, Identifiable {
    case general, notifications, profile, appearance, account, personalization, shortcuts, usage
    case memory, storage, privacy, devices, connections, mcp, updates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "Общие"
        case .notifications: "Уведомления"
        case .profile: "Профиль"
        case .appearance: "Оформление"
        case .account: "Учётная запись"
        case .personalization: "Персонализация"
        case .shortcuts: "Горячие клавиши"
        case .usage: "Использование и подписка"
        case .memory: "Память агентов"
        case .storage: "Файлы и данные"
        case .devices: "Устройства"
        case .privacy: "Данные и приватность"
        case .connections: "Приложения"
        case .mcp: "MCP-серверы"
        case .updates: "Обновления"
        }
    }
    var group: String {
        switch self {
        case .memory, .storage, .privacy, .devices: "Пространство"
        case .connections, .mcp, .updates: "Интеграции"
        default: "Личное"
        }
    }
    var glyph: BlotGlyph {
        switch self {
        case .general: .settings
        case .notifications: .bell
        case .profile: .person
        case .appearance: .sun
        case .account: .card
        case .personalization: .sliders
        case .shortcuts: .returnKey
        case .usage: .usage
        case .memory: .memory
        case .storage: .folder
        case .devices: .network
        case .privacy: .shieldCheck
        case .connections: .puzzle
        case .mcp: .network
        case .updates: .download
        }
    }
    var detail: String {
        switch self {
        case .general: "Язык, запуск приложения и отправка сообщений."
        case .notifications: "События, о которых сообщают ваши агенты."
        case .profile: "Ваше имя в личном пространстве."
        case .appearance: "Тема, движение и плотность интерфейса."
        case .account: "Пространство, команда и текущий план."
        case .personalization: "Роль и инструкции для новых агентов."
        case .shortcuts: "Быстрый доступ к действиям с клавиатуры."
        case .usage: "Действия команды, лимиты и подписка."
        case .memory: "Общий контекст и воспоминания отдельных агентов."
        case .storage: "Локальные документы, переписки и экспорт пространства."
        case .devices: "Доверие iPhone и Mac, передача задач и отзыв доступа."
        case .privacy: "Хранение данных и разрешения подключённых аккаунтов."
        case .connections: "Ваши сервисы и аккаунты для работы команды."
        case .mcp: "Подключение инструментов через Composio, Zapier и MCP."
        case .updates: "Версия приложения и предпочтения обновления."
        }
    }
    func matches(_ query: String) -> Bool {
        let keywords: String = switch self {
        case .general: "Enter ввод подсказки английский русский голос звонок распознавание расшифровка voice speech recognition transcription"
        case .appearance: "светлая тёмная системная анимации уменьшить компактные"
        case .personalization: "задача обучение шаблон"
        case .connections: "Gmail Calendar Drive Slack Notion"
        case .usage: "Pro оплата недельный месячный предел"
        default: ""
        }
        return (["en", "ru"].map { WorkspaceCopy.text(title, language: $0) + " " + WorkspaceCopy.text(detail, language: $0) }.joined(separator: " ") + " " + keywords + " language system theme light dark motion compact tasks subscription billing").localizedCaseInsensitiveContains(query)
    }
}

enum MacTeamPreferenceKey {
    static let sendOnReturn = "blot.mac.sendOnReturn"
    static let composerHints = "blot.mac.composerHints"
    static let compactMessages = "blot.mac.compactMessages"
    static let defaultRole = "blot.mac.defaultAgentRole"
    static let defaultInstructions = "blot.mac.defaultAgentInstructions"
}
