import CryptoKit
import Foundation

public enum MCPError: Error, Equatable, Sendable, LocalizedError {
    case configuration, unavailable, protocolViolation, version, timeout, responseTooLarge, remote(Int), http(Int), accessChanged, uncertain, denied
    public var errorDescription: String? {
        switch self {
        case .configuration: "Проверьте адрес, команду и параметры MCP-сервера. Для сети требуется HTTPS, для stdio — явное доверие."
        case .unavailable: "MCP-сервер недоступен. Проверьте подключение и права запуска."
        case .protocolViolation: "MCP-сервер вернул некорректное сообщение."
        case .version: "Сервер не поддерживает MCP 2025-11-25 или инструменты."
        case .timeout: "MCP-сервер не ответил вовремя."
        case .responseTooLarge: "Ответ MCP-сервера превышает допустимый размер."
        case .remote(let code): "MCP-сервер отклонил запрос (\(code))."
        case .http(let code): "MCP-сервер вернул HTTP \(code). Проверьте адрес и токен."
        case .accessChanged: "Доступ или схема MCP изменились. Проверьте сервер и заново выберите инструменты."
        case .uncertain: "Исход MCP-действия неизвестен. Проверьте результат на сервере перед новыми вызовами."
        case .denied: "Пользователь отклонил MCP-вызов."
        }
    }
}

public struct MCPConfiguration: Codable, Equatable, Sendable {
    public enum Transport: String, Codable, Sendable { case http, stdio }
    public var transport: Transport
    public var endpoint: String
    public var arguments: [String]
    public var workingDirectory: String
    public var environment: [String: String]
    public var bearerToken: String
    public var timeout: Double
    public var trustedLocalProcess: Bool
    public var executableBookmark: Data?
    public var directoryBookmark: Data?
    public init(transport: Transport = .http, endpoint: String = "", arguments: [String] = [], workingDirectory: String = "",
                environment: [String: String] = [:], bearerToken: String = "", timeout: Double = 60, trustedLocalProcess: Bool = false) {
        self.transport = transport; self.endpoint = endpoint; self.arguments = arguments; self.workingDirectory = workingDirectory
        self.environment = environment; self.bearerToken = bearerToken; self.timeout = timeout; self.trustedLocalProcess = trustedLocalProcess
    }
    public func validate() throws {
        guard (1...300).contains(timeout), endpoint.utf8.count <= 2048, arguments.count <= 100,
              arguments.allSatisfy({ $0.utf8.count <= 8192 && !$0.contains("\0") }),
              environment.count <= 50, environment.allSatisfy({ key, value in
                  key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil && value.utf8.count <= 8192 && !value.contains("\0")
              }), bearerToken.utf8.count <= 8192, !bearerToken.contains(where: { $0.isNewline }) else { throw MCPError.configuration }
        switch transport {
        case .http:
            guard let url = URL(string: endpoint), url.scheme == "https" || url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(url.host),
                  url.host != nil, url.user == nil, url.password == nil, url.fragment == nil, url.query == nil,
                  arguments.isEmpty, environment.isEmpty, workingDirectory.isEmpty else { throw MCPError.configuration }
        case .stdio:
            #if os(macOS)
            guard trustedLocalProcess, endpoint.hasPrefix("/"), workingDirectory.hasPrefix("/"),
                  !endpoint.contains("\0"), !workingDirectory.contains("\0"), bearerToken.isEmpty else { throw MCPError.configuration }
            #else
            throw MCPError.configuration
            #endif
        }
    }
    var secrets: [String] { ([bearerToken] + Array(environment.values)).filter { !$0.isEmpty } }
}

public struct MCPTool: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let description: String
    public let inputSchema: ChatJSON
    public var id: String { name }
    init(_ json: ChatJSON) throws {
        guard case .object(let fields) = json, case .string(let name) = fields["name"],
              !name.isEmpty, name.utf8.count <= 128, case .object = fields["inputSchema"] else { throw MCPError.protocolViolation }
        self.name = name; inputSchema = fields["inputSchema"]!
        if case .string(let text) = fields["description"] { description = String(text.prefix(4000)) } else { description = name }
    }
    public func toolID(connectionID: UUID, configurationID: UUID) -> String {
        let data = (try? WorkspaceCoding.encode(self)) ?? Data()
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "mcp_" + connectionID.uuidString.replacingOccurrences(of: "-", with: "").prefix(16) + "_" + configurationID.uuidString.prefix(8) + "_" + digest
    }
}

extension ChatJSON {
    var mcpFields: [String: ChatJSON] { if case .object(let fields) = self { fields } else { [:] } }
    var mcpString: String? { if case .string(let text) = self { text } else { nil } }
    func mcpContains(_ strings: [String]) -> Bool {
        switch self {
        case .string(let text): strings.contains(where: text.contains)
        case .array(let values): values.contains { $0.mcpContains(strings) }
        case .object(let fields): fields.contains { key, value in strings.contains(where: key.contains) || value.mcpContains(strings) }
        default: false
        }
    }
}

public protocol MCPTransport: Sendable {
    func exchange(_ message: ChatJSON) async throws -> ChatJSON?
    func close() async
}
