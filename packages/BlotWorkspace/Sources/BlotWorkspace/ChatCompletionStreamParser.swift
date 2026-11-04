import Foundation

/// No function is published until the entire SSE response has completed and its JSON is valid.
struct ChatCompletionStreamParser {
    enum Dialect: Sendable { case compatible, gigaChat }
    private struct PendingCall {
        var id = ""
        var name = ""
        var arguments = ""
        var object: ChatJSON?
        var stateID: String?
    }
    private let dialect: Dialect
    private var data: [String] = []
    private var eventSize = 0
    private var calls: [Int: PendingCall] = [:]
    private var reason: ChatModelFinish?
    private var usage: ChatModelUsage?
    private(set) var isComplete = false
    init(dialect: Dialect = .compatible) { self.dialect = dialect }

    mutating func consume(line: String) throws -> [ChatModelEvent] {
        guard !isComplete else { return [] }
        guard line.utf8.count <= 1_048_576 else { throw ChatModelError.invalidStream }
        if line.hasPrefix("data:") {
            let value = String(line.dropFirst(5))
            eventSize += value.utf8.count
            guard eventSize <= 1_048_576 else { throw ChatModelError.invalidStream }
            data.append(value.hasPrefix(" ") ? String(value.dropFirst()) : value)
            return []
        }
        guard line.isEmpty, !data.isEmpty else { return [] }
        let payload = data.joined(separator: "\n")
        data.removeAll(keepingCapacity: true); eventSize = 0
        if payload == "[DONE]" {
            guard let reason else { throw ChatModelError.interrupted }
            var events: [ChatModelEvent] = []
            if reason == .toolCalls {
                guard !calls.isEmpty else { throw ChatModelError.invalidStream }
                for index in calls.keys.sorted() {
                    let call = calls[index]!
                    guard !call.name.isEmpty, call.name.utf8.count <= 64,
                          call.name.range(of: "^[A-Za-z_][A-Za-z0-9_-]*$", options: .regularExpression) != nil else {
                        throw ChatModelError.invalidStream
                    }
                    let arguments = try call.object ?? JSONDecoder().decode(ChatJSON.self, from: Data(call.arguments.utf8))
                    guard case .object = arguments else { throw ChatModelError.invalidStream }
                    guard dialect == .gigaChat || !call.id.isEmpty else { throw ChatModelError.invalidStream }
                    events.append(.toolCall(.init(id: call.id.isEmpty ? UUID().uuidString : call.id,
                        name: call.name, arguments: arguments, stateID: call.stateID)))
                }
            } else if !calls.isEmpty { throw ChatModelError.interrupted }
            if let usage { events.append(.usage(usage)) }
            events.append(.finished(reason)); isComplete = true
            return events
        }
        struct Chunk: Decodable {
            struct Usage: Decodable { let prompt_tokens: Int; let completion_tokens: Int }
            struct Choice: Decodable {
                struct Function: Decodable { let name: String?; let arguments: ChatJSON? }
                struct Tool: Decodable { let index: Int; let id: String?; let function: Function? }
                struct Delta: Decodable {
                    let content: String?
                    let tool_calls: [Tool]?
                    let function_call: Function?
                    let functions_state_id: String?
                }
                let delta: Delta
                let finish_reason: String?
            }
            let choices: [Choice]?
            let usage: Usage?
            let error: ChatJSON?
        }
        let chunk = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8))
        guard chunk.error == nil else { throw ChatModelError.providerFailure }
        if let value = chunk.usage { usage = try .init(inputTokens: value.prompt_tokens, outputTokens: value.completion_tokens) }
        guard let choices = chunk.choices, choices.count <= 1 else { throw ChatModelError.unsupportedResponse }
        var events: [ChatModelEvent] = []
        for choice in choices {
            guard reason == nil else { throw ChatModelError.invalidStream }
            if let text = choice.delta.content, !text.isEmpty { events.append(.text(text)) }
            if let function = choice.delta.function_call {
                guard dialect == .gigaChat, calls.isEmpty, let name = function.name,
                      let arguments = function.arguments, case .object = arguments else { throw ChatModelError.invalidStream }
                calls[0] = PendingCall(name: name, object: arguments, stateID: choice.delta.functions_state_id)
            }
            for tool in choice.delta.tool_calls ?? [] {
                guard dialect == .compatible, (0..<64).contains(tool.index) else { throw ChatModelError.invalidStream }
                var call = calls[tool.index] ?? PendingCall()
                if let id = tool.id { call.id += id }
                if let name = tool.function?.name { call.name += name }
                if let argument = tool.function?.arguments {
                    guard case .string(let text) = argument else { throw ChatModelError.invalidStream }
                    call.arguments += text
                }
                guard call.arguments.utf8.count <= 1_048_576, call.id.utf8.count <= 256 else { throw ChatModelError.invalidStream }
                calls[tool.index] = call
            }
            if let finish = choice.finish_reason {
                switch finish {
                case "stop": reason = .stop
                case "tool_calls" where dialect == .compatible: reason = .toolCalls
                case "function_call" where dialect == .gigaChat: reason = .toolCalls
                case "length": reason = .length
                default: throw ChatModelError.providerFailure
                }
            }
        }
        return events
    }
}
