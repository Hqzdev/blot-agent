import Foundation

/// Публичные настройки установки. Паролей, ключей и путей к .env здесь нет.
public struct InstallationSetup: Decodable, Sendable {
    public let emailManaged: Bool
    public let providerManaged: Bool
    public let modelSettings: ModelSettings?

    public struct ModelSettings: Decodable, Sendable {
        public let model: String
        public let contextTokens: Int
        public let outputTokens: Int
        public let runTokenBudget: Int64
    }
}
