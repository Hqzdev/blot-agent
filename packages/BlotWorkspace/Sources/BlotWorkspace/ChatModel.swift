import Foundation

public indirect enum ChatJSON: Codable, Equatable, Sendable {
    case object([String: ChatJSON]), array([ChatJSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode([String: ChatJSON].self) { self = .object(v) }
        else { self = .array(try value.decode([ChatJSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }
}

public struct ChatToolCall: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let arguments: ChatJSON
    public let stateID: String?
    public init(id: String, name: String, arguments: ChatJSON, stateID: String? = nil) {
        self.id = id; self.name = name; self.arguments = arguments; self.stateID = stateID
    }
}

public struct ChatModelMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String
    public let toolCalls: [ChatToolCall]
    public let toolCallID: String?
    public let name: String?
    public init(role: String, content: String, toolCalls: [ChatToolCall] = [], toolCallID: String? = nil, name: String? = nil) {
        self.role = role; self.content = content; self.toolCalls = toolCalls; self.toolCallID = toolCallID; self.name = name
    }
}

public struct ChatToolDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let parameters: ChatJSON
    public init(name: String, description: String, parameters: ChatJSON) {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

public struct ChatModelRequest: Codable, Equatable, Sendable {
    public let messages: [ChatModelMessage]
    public let tools: [ChatToolDefinition]
    public let maximumOutputTokens: Int
    public let requiredTool: String?
    public init(messages: [ChatModelMessage], tools: [ChatToolDefinition] = [], maximumOutputTokens: Int = 2048, requiredTool: String? = nil) {
        self.messages = messages; self.tools = tools; self.maximumOutputTokens = maximumOutputTokens; self.requiredTool = requiredTool
    }
}

public struct ChatModelUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public var totalTokens: Int { inputTokens + outputTokens }
    public init(inputTokens: Int, outputTokens: Int) throws {
        guard inputTokens >= 0, outputTokens >= 0, inputTokens <= Int.max - outputTokens else { throw ChatModelError.invalidStream }
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }
}

public enum ChatModelFinish: String, Codable, Sendable { case stop, toolCalls, length }
public enum ChatModelEvent: Equatable, Sendable {
    case text(String), toolCall(ChatToolCall), usage(ChatModelUsage), finished(ChatModelFinish), failure(ChatModelError)
}
public protocol ChatModel: Sendable {
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error>
}
public enum ChatModelError: Error, Equatable, Sendable {
    case invalidConfiguration, http(Int), transport(Int), invalidStream, unsupportedResponse, interrupted, providerFailure
}

public struct CompatibleChatModel: ChatModel {
    private let endpoint: URL
    private let model: String
    private let apiKey: String
    private let session: URLSession
    public init(endpoint: URL, model: String, apiKey: String, session: URLSession? = nil) throws {
        try ModelHTTP.validate(endpoint: endpoint, model: model, secret: apiKey)
        self.endpoint = endpoint; self.model = model; self.apiKey = apiKey; self.session = session ?? ModelHTTP.makeSession()
    }
    public func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        ModelHTTP.stream(session: session, dialect: .compatible) {
            var body = try ModelRequestEncoder.compatible(request, model: model)
            body["stream_options"] = ["include_usage": true]
            return try ModelHTTP.request(endpoint: endpoint, token: apiKey, body: body)
        }
    }
}
