import Foundation
import Testing
@testable import BlotWorkspace

@Test func streamParsesDeltasAndRequiresExplicitEnd() throws {
    var parser = ChatCompletionStreamParser()
    #expect(try parser.consume(line: ": heartbeat").isEmpty)
    #expect(try parser.consume(line: #"data: {"choices":[{"delta":{"content":"Привет 👋"},"finish_reason":null}]}"#).isEmpty)
    #expect(try parser.consume(line: "") == [.text("Привет 👋")])
    #expect(!parser.isComplete)
    _ = try parser.consume(line: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
    _ = try parser.consume(line: "")
    #expect(!parser.isComplete)
    _ = try parser.consume(line: "data: [DONE]")
    _ = try parser.consume(line: "")
    #expect(parser.isComplete)
}

@Test func truncatedOrToolStreamCannotMasqueradeAsCompletedText() throws {
    var truncated = ChatCompletionStreamParser()
    _ = try truncated.consume(line: "data: [DONE]")
    #expect(throws: ChatModelError.interrupted) { _ = try truncated.consume(line: "") }
    var tool = ChatCompletionStreamParser()
    _ = try tool.consume(line: #"data: {"choices":[{"delta":{"tool_calls":[{}]},"finish_reason":null}]}"#)
    #expect(throws: DecodingError.self) { _ = try tool.consume(line: "") }
    var limited = ChatCompletionStreamParser()
    _ = try limited.consume(line: #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#)
    _ = try limited.consume(line: "")
    _ = try limited.consume(line: "data: [DONE]")
    #expect(try limited.consume(line: "") == [.finished(.length)])
}

@Test func plaintextOrCredentialBearingURLsAreRejectedBeforeNetwork() throws {
    for url in ["http://example.com/v1/chat/completions", "https://user:password@example.com/chat", "https://example.com/chat?api_key=secret"] {
        #expect(throws: ChatModelError.invalidConfiguration) {
            _ = try CompatibleChatModel(endpoint: URL(string: url)!, model: "example", apiKey: "test-only")
        }
    }
}

private func event(_ payload: String, parser: inout ChatCompletionStreamParser) throws -> [ChatModelEvent] {
    _ = try parser.consume(line: "data: " + payload)
    return try parser.consume(line: "")
}

@Test func gigaChatFunctionsKeepObjectArgumentsAndStateUntilDone() throws {
    var parser = ChatCompletionStreamParser(dialect: .gigaChat)
    #expect(try event(#"{"choices":[{"delta":{"function_call":{"name":"file_read","arguments":{"artifact_id":"abc"}},"functions_state_id":"state-1"},"finish_reason":"function_call"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}"#, parser: &parser).isEmpty)
    #expect(!parser.isComplete)
    let events = try event("[DONE]", parser: &parser)
    #expect(events.count == 3)
    guard case .toolCall(let call) = events.first else { Issue.record("Missing completed call"); return }
    #expect(call.name == "file_read")
    #expect(call.stateID == "state-1")
    #expect(call.arguments == .object(["artifact_id": .string("abc")]))
    #expect(events[1] == .usage(try .init(inputTokens: 10, outputTokens: 5)))
    #expect(events[2] == .finished(.toolCalls))
}

@Test func fragmentedCompatibleCallsAndUsageArePublishedOnce() throws {
    var parser = ChatCompletionStreamParser()
    _ = try event(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"file_read","arguments":"{\"artifact_"}}]},"finish_reason":null}]}"#, parser: &parser)
    _ = try event(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"id\":\"abc\"}"}}]},"finish_reason":"tool_calls"}]}"#, parser: &parser)
    _ = try event(#"{"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":6}}"#, parser: &parser)
    let events = try event("[DONE]", parser: &parser)
    #expect(events.filter { if case .toolCall = $0 { true } else { false } }.count == 1)
    #expect(events.filter { if case .usage = $0 { true } else { false } }.count == 1)
    #expect(try event("[DONE]", parser: &parser).isEmpty)
}

@Test func malformedOrTruncatedFunctionNeverReachesTools() throws {
    var parser = ChatCompletionStreamParser()
    #expect(try event(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"file_read","arguments":"{broken"}}]},"finish_reason":"tool_calls"}]}"#, parser: &parser).isEmpty)
    #expect(throws: (any Error).self) { _ = try event("[DONE]", parser: &parser) }
    #expect(!parser.isComplete)
}

@Test func gigaChatRequestUsesNativeFunctionHistoryAndPreservesState() throws {
    let call = ChatToolCall(id: "call", name: "file_read", arguments: .object(["artifact_id": .string("abc")]), stateID: "state-1")
    let request = ChatModelRequest(messages: [.init(role: "system", content: "Agent instructions"),
        .init(role: "system", content: "Runtime instructions"), .init(role: "assistant", content: "", toolCalls: [call]),
        .init(role: "tool", content: "{}", toolCallID: "call", name: "file_read")])
    let body = try ModelRequestEncoder.gigaChat(request, model: "GigaChat")
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.map { $0["role"] as? String } == ["system", "assistant", "function"])
    #expect(messages[1]["functions_state_id"] as? String == "state-1")
    #expect((messages[1]["function_call"] as? [String: Any])?["arguments"] is [String: Any])
    #expect(messages[2]["name"] as? String == "file_read")
    #expect(messages[2]["tool_call_id"] == nil)
}

@Test func gigaChatCombinesSystemContextWithoutChangingSeparateRepliesOrHistory() throws {
    let request = ChatModelRequest(messages: [
        .init(role: "system", content: "Runtime rules"), .init(role: "system", content: "Agent instructions"),
        .init(role: "user", content: "Inspect this"), .init(role: "assistant", content: "I'll check."),
        .init(role: "assistant", content: "Checked."), .init(role: "system", content: "Approved memory"),
        .init(role: "user", content: "What next?")
    ])
    let body = try ModelRequestEncoder.gigaChat(request, model: "GigaChat")
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.map { $0["role"] as? String } == ["system", "user", "assistant", "assistant", "user"])
    #expect(messages.map { $0["content"] as? String } == [
        "Runtime rules\n\nAgent instructions\n\nApproved memory", "Inspect this", "I'll check.", "Checked.", "What next?"
    ])
    let compatible = try ModelRequestEncoder.compatible(request, model: "compatible")
    let original = try #require(compatible["messages"] as? [[String: Any]])
    #expect(original.map { $0["content"] as? String } == request.messages.map(\.content))
}

@Test func gigaChatDoesNotAddSystemInstructionsToPlainConversation() throws {
    let body = try ModelRequestEncoder.gigaChat(.init(messages: [.init(role: "user", content: "Hello")]), model: "GigaChat")
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages[0]["role"] as? String == "user")
    #expect(messages[0]["content"] as? String == "Hello")
}

@Test func exactToolSelectionUsesNativeProviderFieldsAndPreservesLegacyRequests() throws {
    let definition = ChatToolDefinition(name: "inspect", description: "Inspect", parameters: .object([:]))
    let request = ChatModelRequest(messages: [.init(role: "user", content: "Inspect this")], tools: [definition], requiredTool: "inspect")
    let giga = try ModelRequestEncoder.gigaChat(request, model: "GigaChat")
    #expect((giga["function_call"] as? [String: String])?["name"] == "inspect")
    let compatible = try ModelRequestEncoder.compatible(request, model: "compatible")
    let choice = try #require(compatible["tool_choice"] as? [String: Any])
    #expect(choice["type"] as? String == "function")
    #expect((choice["function"] as? [String: String])?["name"] == "inspect")
    for tools in [[], [definition]] {
        let invalid = ChatModelRequest(messages: [], tools: tools, requiredTool: "unavailable")
        #expect(throws: ChatModelError.invalidConfiguration) { _ = try ModelRequestEncoder.gigaChat(invalid, model: "GigaChat") }
        #expect(throws: ChatModelError.invalidConfiguration) { _ = try ModelRequestEncoder.compatible(invalid, model: "compatible") }
    }
    let old = try JSONDecoder().decode(ChatModelRequest.self, from: Data(#"{"messages":[],"tools":[],"maximumOutputTokens":64}"#.utf8))
    #expect(old.requiredTool == nil)
}
