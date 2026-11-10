import Foundation

/// Credentials are never forwarded to a different origin, including redirects.
final class ModelRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

enum ModelHTTP {
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        return URLSession(configuration: config, delegate: ModelRedirectPolicy(), delegateQueue: nil)
    }
    static func validate(endpoint: URL, model: String, secret: String) throws {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secret.contains(where: { $0.isNewline }) else { throw ChatModelError.invalidConfiguration }
    }
    static func request(endpoint: URL, token: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
    static func stream(session: URLSession, dialect: ChatCompletionStreamParser.Dialect,
                       onUnauthorized: (@Sendable () async -> Void)? = nil,
                       makeRequest: @escaping @Sendable () async throws -> URLRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let request = try await makeRequest()
                    try Task.checkCancellation()
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse else { throw ChatModelError.invalidStream }
                    if response.statusCode == 401 { await onUnauthorized?() }
                    guard (200..<300).contains(response.statusCode) else { throw ChatModelError.http(response.statusCode) }
                    guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else {
                        throw ChatModelError.invalidStream
                    }
                    var parser = ChatCompletionStreamParser(dialect: dialect)
                    var line = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if byte == 10 {
                            if line.last == 13 { line.removeLast() }
                            guard let text = String(data: line, encoding: .utf8) else { throw ChatModelError.invalidStream }
                            line.removeAll(keepingCapacity: true)
                            for event in try parser.consume(line: text) { continuation.yield(event) }
                            if parser.isComplete { break }
                        } else {
                            guard line.count < 1_048_576 else { throw ChatModelError.invalidStream }
                            line.append(byte)
                        }
                    }
                    guard parser.isComplete else { throw ChatModelError.interrupted }
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.failure(error as? ChatModelError ?? .transport((error as NSError).code)))
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}

enum ModelRequestEncoder {
    static func compatible(_ request: ChatModelRequest, model: String) throws -> [String: Any] {
        guard request.maximumOutputTokens > 0 else { throw ChatModelError.invalidConfiguration }
        let messages = try request.messages.map { message -> [String: Any] in
            var value: [String: Any] = ["role": message.role, "content": message.content]
            if let id = message.toolCallID { value["tool_call_id"] = id }
            if let name = message.name { value["name"] = name }
            if !message.toolCalls.isEmpty {
                value["tool_calls"] = try message.toolCalls.map { call in
                    ["id": call.id, "type": "function", "function": ["name": call.name,
                        "arguments": String(decoding: try JSONEncoder().encode(call.arguments), as: UTF8.self)]] as [String: Any]
                }
            }
            return value
        }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "max_tokens": request.maximumOutputTokens]
        if !request.tools.isEmpty {
            body["tools"] = try request.tools.map { tool in ["type": "function", "function": try object(tool)] as [String: Any] }
            body["tool_choice"] = "auto"
        }
        return body
    }
    static func gigaChat(_ request: ChatModelRequest, model: String) throws -> [String: Any] {
        guard request.maximumOutputTokens > 0 else { throw ChatModelError.invalidConfiguration }
        // GigaChat requires a single system message at the start, including memory and runtime instructions.
        let instructions = request.messages.filter { $0.role == "system" }
        let history = request.messages.filter { $0.role != "system" }
        let input = instructions.isEmpty ? history
            : [ChatModelMessage(role: "system", content: instructions.map(\.content).joined(separator: "\n\n"))] + history
        let messages = try input.map { message -> [String: Any] in
            var value: [String: Any] = ["role": message.role == "tool" ? "function" : message.role, "content": message.content]
            if let name = message.name { value["name"] = name }
            if let call = message.toolCalls.first {
                guard message.toolCalls.count == 1 else { throw ChatModelError.unsupportedResponse }
                value["function_call"] = ["name": call.name, "arguments": try object(call.arguments)]
                value["functions_state_id"] = call.stateID
            }
            return value
        }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "max_tokens": request.maximumOutputTokens]
        if !request.tools.isEmpty { body["functions"] = try request.tools.map { try object($0) }; body["function_call"] = "auto" }
        return body
    }
    private static func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
}
