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
        if let model = error as? ChatModelError {
            switch model {
            case .http(401), .http(403): return "Провайдер ИИ отклонил доступ. Проверьте ключ и права на модель. Сообщение сохранено."
            case .http(402): return "У провайдера ИИ закончился доступный баланс или пакет токенов. Сообщение сохранено."
            case .http(429): return "Провайдер ИИ ограничил частоту запросов. Повторите ответ немного позже."
            case .http(let status): return "Провайдер ИИ вернул ошибку HTTP \(status). Сообщение сохранено; можно повторить ответ."
            case .invalidConfiguration: return "Не настроено подключение выбранной модели. Проверьте модель и ключ."
            case .transport(let code) where code == URLError.secureConnectionFailed.rawValue || code == URLError.serverCertificateUntrusted.rawValue:
                return "Не удалось установить защищённое соединение с провайдером ИИ. Проверьте сеть и настройки VPN. Сообщение сохранено."
            case .transport: return "Не удалось подключиться к провайдеру ИИ. Проверьте сеть. Сообщение сохранено."
            case .invalidStream, .unsupportedResponse, .providerFailure: return "Провайдер ИИ вернул некорректный ответ. Сообщение сохранено; можно повторить ответ."
            case .interrupted: return "Ответ ИИ прерван. Полученная часть сохранена; можно повторить ответ."
            }
        }
        if error as? WorkspaceStorageError == .permissionDenied { return "Рабочее пространство уже открыто другим процессом или действие не разрешено." }
        return "Не удалось выполнить действие. Введённые и сохранённые данные сохранены."
    }
}
