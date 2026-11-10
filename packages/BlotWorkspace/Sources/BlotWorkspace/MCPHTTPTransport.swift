import Foundation

/// Credentials never cross redirects. Each session belongs to exactly one configured endpoint.
public actor MCPHTTPTransport: MCPTransport {
    private let configuration: MCPConfiguration
    private let session: URLSession
    private var sessionID: String?
    private var initialized = false
    private var closed = false
    public init(configuration: MCPConfiguration) throws {
        try configuration.validate()
        guard configuration.transport == .http else { throw MCPError.configuration }
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = configuration.timeout; settings.timeoutIntervalForResource = configuration.timeout
        settings.httpCookieStorage = nil; settings.urlCache = nil; settings.urlCredentialStorage = nil
        session = URLSession(configuration: settings, delegate: MCPNoRedirects(), delegateQueue: nil)
    }
    public func exchange(_ message: ChatJSON) async throws -> ChatJSON? {
        guard !closed else { throw MCPError.unavailable }
        var request = URLRequest(url: URL(string: configuration.endpoint)!)
        request.httpMethod = "POST"; request.httpBody = try WorkspaceCoding.encode(message)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if !configuration.bearerToken.isEmpty { request.setValue("Bearer " + configuration.bearerToken, forHTTPHeaderField: "Authorization") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if initialized { request.setValue(MCPClient.version, forHTTPHeaderField: "MCP-Protocol-Version") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw MCPError.protocolViolation }
        guard (200...299).contains(response.statusCode) else { throw MCPError.http(response.statusCode) }
        if let id = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            guard id.utf8.count <= 1024, !id.isEmpty, id.utf8.allSatisfy({ (33...126).contains($0) }), sessionID == nil || sessionID == id else { throw MCPError.protocolViolation }
            sessionID = id
        }
        if message.mcpFields["method"]?.mcpString == "notifications/initialized" { initialized = true }
        guard let expectedID = message.mcpFields["id"], message.mcpFields["method"] != nil else {
            guard response.statusCode == 202 else { throw MCPError.protocolViolation }; return nil
        }
        let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard type.hasPrefix("application/json") || type.hasPrefix("text/event-stream") else { throw MCPError.protocolViolation }
        var body = Data(), line = Data(), event: [String] = []
        var total = 0
        for try await byte in bytes {
            try _Concurrency.Task.checkCancellation()
            total += 1; guard total <= 1_048_576 else { throw MCPError.responseTooLarge }
            if type.hasPrefix("application/json") { body.append(byte); continue }
            if byte != 10 { line.append(byte); continue }
            let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .newlines); line.removeAll(keepingCapacity: true)
            if text.isEmpty {
                if !event.isEmpty {
                    let payload = event.joined(separator: "\n"); event.removeAll(keepingCapacity: true)
                    if !payload.isEmpty {
                        let value = try JSONDecoder().decode(ChatJSON.self, from: Data(payload.utf8))
                        if let result = try await handle(value, expectedID: expectedID) { return result }
                    }
                }
            } else if text.hasPrefix("data:") {
                let data = text.dropFirst(5); event.append(String(data.first == " " ? data.dropFirst() : data))
            }
        }
        guard type.hasPrefix("application/json") else { throw MCPError.unavailable }
        let value = try JSONDecoder().decode(ChatJSON.self, from: body)
        guard value.mcpFields["id"] == expectedID else { throw MCPError.protocolViolation }
        return value
    }
    private func handle(_ value: ChatJSON, expectedID: ChatJSON) async throws -> ChatJSON? {
        let fields = value.mcpFields
        guard fields["jsonrpc"] == .string("2.0") else { throw MCPError.protocolViolation }
        if let method = fields["method"]?.mcpString {
            if let id = fields["id"] {
                let reply: ChatJSON = method == "ping"
                    ? .object(["jsonrpc": .string("2.0"), "id": id, "result": .object([:])])
                    : .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(-32601), "message": .string("Client capability not supported")])])
                _ = try await exchange(reply)
            }
            return nil
        }
        guard fields["id"] == expectedID else { throw MCPError.protocolViolation }
        return value
    }
    public func close() { closed = true; session.invalidateAndCancel() }
}

private final class MCPNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
