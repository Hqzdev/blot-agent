import BlotWorkspace
import Foundation

/// Product errors contain no remote response bodies, tokens, addresses or secret values.
enum WorkspaceFailureCopy {
    static func message(_ error: any Error) -> String {
        if let cloud = error as? WorkspaceCloudError {
            switch cloud {
            case .rejected(_, "email_not_verified"): return "Подтвердите почту кодом из письма."
            case .rejected(_, "invalid_credentials"): return "Неверная почта или пароль."
            case .rejected(_, "code_expired_or_invalid"): return "Код неверен или истёк. Запросите новый код."
            case .rejected(429, _): return "Слишком много попыток. Попробуйте позже."
            case .authenticationRequired: return "Войдите в аккаунт заново."
            default: return "Сервис аккаунтов временно недоступен. Введённые данные сохранены."
            }
        }
        if error is URLError { return "Нет соединения с сервисом. Проверьте сеть и повторите действие." }
        if error is ChatModelError { return "Не удалось получить ответ модели. Сообщение сохранено; повторите ответ из его меню." }
        if error as? WorkspaceStorageError == .permissionDenied { return "Рабочее пространство уже открыто другим процессом или действие не разрешено." }
        return "Не удалось выполнить действие. Введённые и сохранённые данные сохранены."
    }
}
