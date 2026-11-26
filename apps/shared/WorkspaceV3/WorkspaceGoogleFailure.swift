import AuthenticationServices
import BlotWorkspace
import Foundation

enum WorkspaceGoogleFailure {
    static func message(_ error: Error, russian: Bool) -> String {
        func text(_ ru: String, _ en: String) -> String { russian ? ru : en }
        switch error {
        case GoogleOAuthError.notConfigured:
            return text("В этой сборке не настроен Google OAuth. Нужен client ID для этого устройства.", "Google OAuth is not configured in this build. A client ID for this device is required.")
        case GoogleOAuthError.invalidConfiguration:
            return text("Настройки Google OAuth не соответствуют этой сборке: проверьте тип клиента, bundle ID и адрес возврата.", "Google OAuth configuration does not match this build. Check client type, bundle ID and redirect URI.")
        case GoogleOAuthError.clientSecretRequired:
            return text("Для клиента Google типа Desktop не задан client_secret. Добавьте конфигурацию клиента Mac и пересоберите Ori. Секрет веб-клиента сюда не подходит.", "The Google Desktop client requires its client_secret. Add the Mac client configuration and rebuild Ori. Do not use the web client secret.")
        case GoogleOAuthError.apiNotEnabled:
            return text("API этого сервиса выключен в проекте Google Cloud. Включите Gmail API, Calendar API или Drive API для выбранного подключения и повторите.", "This service API is disabled in Google Cloud. Enable Gmail API, Calendar API or Drive API for this connection and try again.")
        case is CancellationError:
            return text("Операция Google отменена.", "Google operation canceled.")
        case GoogleOAuthError.invalidCallback:
            return text("Google вернул неподходящий адрес или состояние входа. Начните подключение заново.", "Google returned an invalid callback or login state. Start a new connection attempt.")
        case GoogleOAuthError.invalidScopes:
            return text("Google не предоставил все разрешения выбранного сервиса. Подключите его заново и проверьте разрешения.", "Google did not grant every permission required by this service. Reconnect and review permissions.")
        case GoogleOAuthError.accessDenied:
            return text("Google отклонил доступ. Проверьте разрешения аккаунта, включённый API и доступ тестового пользователя.", "Google denied access. Check account permissions, the enabled API and test-user access.")
        case GoogleOAuthError.authorizationExpired:
            return text("Сеанс Google истёк или код входа отклонён. Подключите аккаунт заново.", "The Google session expired or the authorization code was rejected. Reconnect the account.")
        case MCPError.unavailable:
            return text("Не удалось открыть системное окно входа. Откройте основное окно Ori и повторите.", "Could not open system sign-in. Open the main Ori window and try again.")
        default:
            let value = error as NSError
            if value.domain == ASWebAuthenticationSessionError.errorDomain {
                if value.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    return text("Вход Google отменён. Доступ не выдан.", "Google sign-in was canceled. No access was granted.")
                }
                return text("Не удалось открыть окно входа Google. Повторите из основного окна Ori.", "Could not open Google sign-in. Try again from the main Ori window.")
            }
            if error is URLError { return text("Нет соединения с Google. Проверьте сеть и повторите.", "Could not reach Google. Check the connection and try again.") }
            return text("Не удалось завершить подключение Google. Код: ", "Could not complete the Google connection. Code: ") + value.domain + ":" + String(value.code)
        }
    }
}
