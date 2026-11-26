import BlotDesign
import Foundation

enum MacTeamSettingsPane: String, CaseIterable, Identifiable {
    case general, notifications, profile, appearance, account, personalization, shortcuts, usage
    case models, memory, storage, privacy, devices, connections, mcp, browser, updates
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
        case .models: "AI models"
        case .memory: "Память агентов"
        case .storage: "Файлы и данные"
        case .devices: "Устройства"
        case .privacy: "Данные и приватность"
        case .connections: "Приложения"
        case .mcp: "MCP-серверы"
        case .browser: "Browser access"
        case .updates: "Обновления"
        }
    }
    var group: String {
        switch self {
        case .memory, .storage, .privacy, .devices: "Пространство"
        case .connections, .mcp, .browser, .updates: "Интеграции"
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
        case .models: .chip
        case .memory: .memory
        case .storage: .folder
        case .devices: .network
        case .privacy: .shieldCheck
        case .connections: .puzzle
        case .mcp: .network
        case .browser: .globe
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
        case .models: "Model settings and API keys."
        case .memory: "Общий контекст и воспоминания отдельных агентов."
        case .storage: "Локальные документы, переписки и экспорт пространства."
        case .devices: "Доверие iPhone и Mac, передача задач и отзыв доступа."
        case .privacy: "Хранение данных и разрешения подключённых аккаунтов."
        case .connections: "Ваши сервисы и аккаунты для работы команды."
        case .mcp: "Подключение инструментов через Composio, Zapier и MCP."
        case .browser: "Browser permissions and profiles."
        case .updates: "Версия приложения и предпочтения обновления."
        }
    }
    func matches(_ query: String) -> Bool {
        let keywords: String = switch self {
        case .general: "Enter ввод подсказки английский русский голос звонок распознавание расшифровка language voice speech recognition transcription"
        case .appearance: "светлая тёмная системная анимации уменьшить компактные theme light dark motion compact"
        case .personalization: "задача обучение шаблон tasks templates"
        case .connections: "Gmail Calendar Drive Slack Notion"
        case .usage: "оплата недельный месячный предел subscription billing payment quota rate limit"
        case .models: "модели ключ провайдер provider endpoint Ori Mini Ori Pro Ori Max"
        case .devices: "устройства Devices iPhone Mac pairing"
        case .browser: "браузер сайты chrome cookie профили"
        default: ""
        }
        let searchableText = ["en", "ru"].map {
            WorkspaceCopy.text(title, language: $0) + " " + WorkspaceCopy.text(detail, language: $0)
        }.joined(separator: " ") + " " + keywords
        let separators = CharacterSet.alphanumerics.inverted
        let words = searchableText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: separators)
        let terms = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: separators).filter { !$0.isEmpty }
        return !terms.isEmpty && terms.allSatisfy { term in
            words.contains { $0.hasPrefix(term) }
        }
    }
}

enum MacTeamPreferenceKey {
    static let sidebarWidth = "blot.mac.workspace.sidebarWidth"
    static let sendOnReturn = "blot.mac.sendOnReturn"
    static let composerHints = "blot.mac.composerHints"
    static let compactMessages = "blot.mac.compactMessages"
    static let defaultRole = "blot.mac.defaultAgentRole"
    static let defaultInstructions = "blot.mac.defaultAgentInstructions"
}
