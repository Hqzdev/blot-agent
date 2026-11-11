import Foundation

public enum WorkspaceBrowserError: String, Error, LocalizedError, Sendable {
    case unavailable, invalidURL, denied, stalePage, busy, unsavedChanges, canceled, unknown, timeout, manualSignIn
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Откройте HTTPS-адрес. HTTP доступен только для localhost."
        case .denied: "Нет доступа к этой вкладке или сайту."
        case .stalePage: "Страница или элемент изменились. Получите новый снимок страницы."
        case .busy: "Лимит живых вкладок достигнут. Закройте вкладку с несохранённой формой или загрузкой."
        case .unsavedChanges: "На странице есть несохранённая форма. Закройте её вручную."
        case .timeout: "Сайт не ответил вовремя. Проверьте страницу перед продолжением."
        case .manualSignIn: "Провайдер запрещает встроенный вход. Требуется действие пользователя."
        case .canceled: "Действие браузера остановлено."
        case .unknown: "Исход действия неизвестен. Проверьте страницу; автоматического повтора нет."
        case .unavailable: "Встроенный браузер недоступен."
        }
    }
}

public enum WorkspaceBrowserURL {
    /// Address-bar input only. Agent navigation continues to require an explicit, validated URL.
    public static func userNavigation(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 8192 else { throw WorkspaceBrowserError.invalidURL }
        if text.contains("://") { return try validated(text) }
        let host = text.components(separatedBy: "/").first ?? text
        let local = host == "localhost" || host.hasPrefix("localhost:") || host.hasPrefix("127.0.0.1") || host.hasPrefix("[::1]")
        if text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, local || host.contains(".") {
            return try validated((local ? "http://" : "https://") + text)
        }
        guard text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) == nil else { throw WorkspaceBrowserError.invalidURL }
        var search = URLComponents(string: "https://www.google.com/search")!
        search.queryItems = [.init(name: "q", value: text)]
        guard let url = search.url else { throw WorkspaceBrowserError.invalidURL }
        return try validated(url.absoluteString)
    }
    public static func validated(_ text: String) throws -> URL {
        guard text.utf8.count <= 8192, let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty, parts.user == nil, parts.password == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)), let url = parts.url else { throw WorkspaceBrowserError.invalidURL }
        return url
    }
    public static func origin(_ url: URL) throws -> String {
        let valid = try validated(url.absoluteString)
        guard var parts = URLComponents(url: valid, resolvingAgainstBaseURL: false) else { throw WorkspaceBrowserError.invalidURL }
        parts.scheme = parts.scheme?.lowercased(); parts.host = parts.host?.lowercased()
        parts.path = ""; parts.query = nil; parts.fragment = nil
        if parts.port == (parts.scheme == "https" ? 443 : 80) { parts.port = nil }
        guard let origin = parts.string else { throw WorkspaceBrowserError.invalidURL }; return origin
    }
    public static func isRestrictedAuthentication(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "accounts.google.com" && (url.path.contains("oauth") || url.path.contains("signin"))
    }
    public static func restorable(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), (try? validated(url.absoluteString)) != nil else { return nil }
        // Authorization callbacks must not be written to local tab history.
        parts.query = nil; parts.fragment = nil
        return parts.url
    }
}

public struct WorkspaceBrowserScope: Codable, Hashable, Sendable {
    public let sourceID: UUID
    public let taskID: UUID?
    public let agentID: UUID
    public init(sourceID: UUID, taskID: UUID?, agentID: UUID) { self.sourceID = sourceID; self.taskID = taskID; self.agentID = agentID }
}
public enum WorkspaceBrowserSessionKey: Codable, Hashable, Sendable {
    case workspace, agent(UUID), group(UUID)
}

public struct WorkspaceBrowserCommand: Sendable {
    public let id: UUID
    public let name: String
    public let arguments: ChatJSON
    public let scope: WorkspaceBrowserScope
    public let origins: Set<String>
    public let sessionKey: WorkspaceBrowserSessionKey
    public init(id: UUID, name: String, arguments: ChatJSON, scope: WorkspaceBrowserScope, origins: Set<String>, sessionKey: WorkspaceBrowserSessionKey = .workspace) {
        self.id = id; self.name = name; self.arguments = arguments; self.scope = scope; self.origins = origins; self.sessionKey = sessionKey
    }
}
public struct WorkspaceBrowserBinding: Codable, Equatable, Sendable {
    public let tabID: UUID
    public let documentID: UUID
    public let url: String
    public let target: String
    public let interactionRevision: Int
    public init(tabID: UUID, documentID: UUID, url: String, target: String = "", interactionRevision: Int = 0) {
        self.tabID = tabID; self.documentID = documentID; self.url = url; self.target = target; self.interactionRevision = interactionRevision
    }
}
public enum WorkspaceBrowserResult: Sendable {
    case value(ChatJSON)
    case image(Data)
}
public protocol WorkspaceBrowserExecuting: Sendable {
    func prepare(_ command: WorkspaceBrowserCommand) async throws -> WorkspaceBrowserBinding
    func execute(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserResult
    func stop(scope: WorkspaceBrowserScope?) async
}
public struct WorkspaceBrowserAccess: Codable, Equatable, Sendable {
    public var agents: Set<UUID>
    public var origins: Set<String>
    public init(agents: Set<UUID> = [], origins: Set<String> = []) { self.agents = agents; self.origins = origins }
}
