import Foundation

/// A bounded tools-only MCP session. Server instructions never become system instructions.
public actor MCPClient {
    public static let version = "2025-11-25"
    private let transport: any MCPTransport
    private var sequence = 0
    private var ready = false
    public init(transport: any MCPTransport) { self.transport = transport }
    public static func connect(configuration: MCPConfiguration) throws -> MCPClient {
        if configuration.transport == .http { return MCPClient(transport: try MCPHTTPTransport(configuration: configuration)) }
        #if os(macOS)
        return MCPClient(transport: try MCPStdioTransport(configuration: configuration))
        #else
        throw MCPError.configuration
        #endif
    }
    private func initialize() async throws {
        guard !ready else { return }
        let result = try await request("initialize", params: .object(["protocolVersion": .string(Self.version), "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("Blot"), "version": .string("1.0")])]))
        guard result.mcpFields["protocolVersion"] == .string(Self.version),
              case .object = result.mcpFields["capabilities"]?.mcpFields["tools"] else { throw MCPError.version }
        _ = try await transport.exchange(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]))
        ready = true
    }
    public func tools() async throws -> [MCPTool] {
        try await initialize()
        var tools: [MCPTool] = [], cursor: String?, seen: Set<String> = []
        for _ in 0..<20 {
            let result = try await request("tools/list", params: .object(cursor.map { ["cursor": .string($0)] } ?? [:]))
            guard case .array(let values) = result.mcpFields["tools"] else { throw MCPError.protocolViolation }
            tools += try values.map(MCPTool.init)
            guard tools.count <= 100, Set(tools.map(\.name)).count == tools.count else { throw MCPError.responseTooLarge }
            guard try WorkspaceCoding.encode(tools).count <= 512 * 1024 else { throw MCPError.responseTooLarge }
            guard let next = result.mcpFields["nextCursor"] else { return tools }
            guard case .string(let value) = next, !value.isEmpty, value.utf8.count <= 2048, seen.insert(value).inserted else { throw MCPError.protocolViolation }
            cursor = value
        }
        throw MCPError.responseTooLarge
    }
    public func call(name: String, arguments: ChatJSON) async throws -> ChatJSON {
        try await initialize()
        let result = try await request("tools/call", params: .object(["name": .string(name), "arguments": arguments]))
        guard case .array = result.mcpFields["content"] else { throw MCPError.protocolViolation }
        // Preserve text and structured JSON. Do not place embedded binary data into model context.
        var fields = result.mcpFields
        if case .array(let blocks) = fields["content"] {
            fields["content"] = .array(blocks.map { block in
                guard block.mcpFields["type"] == .string("text") || block.mcpFields["type"] == .string("resource_link") else {
                    return .object(["type": .string("text"), "text": .string("[Non-text MCP content omitted]")])
                }
                return block
            })
        }
        let filtered = ChatJSON.object(fields)
        guard try WorkspaceCoding.encode(filtered).count <= 56 * 1024 else { throw MCPError.responseTooLarge }
        return filtered
    }
    private func request(_ method: String, params: ChatJSON) async throws -> ChatJSON {
        try _Concurrency.Task.checkCancellation()
        sequence += 1; let id = ChatJSON.number(Double(sequence))
        guard let response = try await transport.exchange(.object(["jsonrpc": .string("2.0"), "id": id, "method": .string(method), "params": params])),
              response.mcpFields["jsonrpc"] == .string("2.0"), response.mcpFields["id"] == id else { throw MCPError.protocolViolation }
        let fields = response.mcpFields
        if let error = fields["error"] {
            guard fields["result"] == nil, case .number(let code) = error.mcpFields["code"], code.isFinite, abs(code) <= Double(Int32.max) else { throw MCPError.protocolViolation }
            throw MCPError.remote(Int(code))
        }
        guard let result = fields["result"] else { throw MCPError.protocolViolation }
        return result
    }
    public func close() async { ready = false; await transport.close() }
}
