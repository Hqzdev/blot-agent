import AVFoundation
import Speech
import Foundation
import Testing
@testable import BlotAppleIntegrations

@Test func voiceTranscriptRevisionsDoNotDuplicateWords() {
    var value = VoiceTranscript()
    value.replace(start: 0, end: 1, text: "Первая")
    value.replace(start: 0, end: 2, text: "Первая проверка.")
    value.replace(start: 2, end: 3, text: "Вторая фраза.")
    #expect(value.text == "Первая проверка. Вторая фраза.")
    value.replace(start: .nan, end: 3, text: "invalid")
    #expect(!value.text.contains("invalid"))
    value.replace(start: 0, end: 2, text: "Исправление.")
    #expect(value.text == "Исправление. Вторая фраза.")
}
@Test func voiceOutputKeepsCodeAndLongAnswersOnScreen() {
    let text = "Создан [документ](https://example.com/a).\n```swift\nprint(123)\n```\n| column | value |\nГотово."
    let spoken = VoiceSpokenText.prepare(text, russian: true)
    #expect(spoken == "Создан документ. Готово.")
    #expect(VoiceSpokenText.prepare("```\ncode\n```", russian: true) == "Результат показан в чате.")
    #expect(VoiceSpokenText.prepare(String(repeating: "Ответ. ", count: 500), russian: true).count < 1800)
}

@MainActor private final class VoiceInputFixture: VoiceRecognizing {
    var capturing = false
    var prepared = 0
    var startCount = 0
    var stopCount = 0
    var text = "Проверь сайт"
    var prepareError: VoiceFailure?
    var update: ((String) -> Void)?
    func prepare(locale: Locale) async throws { prepared += 1; if let prepareError { throw prepareError } }
    func start(update: @escaping @MainActor (String) -> Void, activity: @escaping @MainActor () -> Void, failure: @escaping @MainActor (Error) -> Void) async throws {
        capturing = true; startCount += 1; self.update = update
    }
    func finish() async throws -> String { capturing = false; return text }
    func stop() async { capturing = false; stopCount += 1; update = nil }
}
@MainActor private final class VoiceOutputFixture: VoiceSpeaking {
    var spoken: [String] = []
    var continuation: CheckedContinuation<Void, Error>?
    func prepare(locale: Locale) throws {}
    func speak(_ text: String) async throws {
        spoken.append(text)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: { Task { @MainActor in self.stop() } }
    }
    func complete() { let old = continuation; continuation = nil; old?.resume() }
    func stop() { let old = continuation; continuation = nil; old?.resume(throwing: CancellationError()) }
}
@MainActor private func waitUntil(_ check: () -> Bool) async throws {
    for _ in 0..<200 {
        if check() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Voice state did not settle")
}

@Suite(.serialized) @MainActor struct VoiceSessionTests {
    @Test func sendsOneFinalTranscriptAndNeverCapturesItsOwnAnswer() async throws {
        let input = VoiceInputFixture(), output = VoiceOutputFixture()
        let session = VoiceConversationSession(input: input, output: output)
        var sent: [String] = []
        session.begin(conversationID: UUID(), locale: .init(identifier: "ru-RU")) { text in sent.append(text); return "Ответ готов." }
        try await waitUntil { session.phase == .listening }
        input.update?("Промежуточный текст")
        session.submit(); session.submit()
        try await waitUntil { session.phase == .speaking }
        #expect(sent == [input.text] && !input.capturing && output.spoken == ["Ответ готов."])
        output.complete()
        try await waitUntil { session.phase == .listening }
        #expect(input.capturing && input.startCount == 2)
        session.end()
        try await waitUntil { !input.capturing }
        #expect(session.phase == .idle)
    }
    @Test func endingWhileModelWorksDiscardsLateReplyAndDoesNotRetry() async throws {
        let input = VoiceInputFixture(), output = VoiceOutputFixture()
        let session = VoiceConversationSession(input: input, output: output)
        var response: CheckedContinuation<String, Error>?
        var calls = 0
        session.begin(conversationID: UUID(), locale: .init(identifier: "ru-RU")) { _ in
            calls += 1
            return try await withCheckedThrowingContinuation { response = $0 }
        }
        try await waitUntil { session.phase == .listening }
        session.submit()
        try await waitUntil { response != nil }
        session.end(); response?.resume(returning: "Запоздавший ответ")
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.phase == .idle && !input.capturing && output.spoken.isEmpty && calls == 1)
    }
    @Test func interruptionDropsPlaybackAndRestartsListeningOnce() async throws {
        let input = VoiceInputFixture(), output = VoiceOutputFixture()
        let session = VoiceConversationSession(input: input, output: output)
        session.begin(conversationID: UUID(), locale: .init(identifier: "ru-RU")) { _ in "Ответ" }
        try await waitUntil { session.phase == .listening }; session.submit()
        try await waitUntil { session.phase == .speaking }; session.interrupt()
        try await waitUntil { session.phase == .listening }
        #expect(output.continuation == nil && output.spoken.count == 1 && input.startCount == 2)
        session.end()
    }
    @Test func muteDuringResponseIsRespectedAfterPlayback() async throws {
        let input = VoiceInputFixture(), output = VoiceOutputFixture()
        let session = VoiceConversationSession(input: input, output: output)
        session.begin(conversationID: UUID(), locale: .init(identifier: "ru-RU")) { _ in "Ответ" }
        try await waitUntil { session.phase == .listening }; session.submit()
        try await waitUntil { session.phase == .speaking }
        session.toggleMute(); output.complete()
        try await waitUntil { session.phase == .muted }
        #expect(!input.capturing && session.microphoneMuted)
        session.toggleMute(); try await waitUntil { session.phase == .listening }
        session.audioInterrupted(); try await waitUntil { !input.capturing }
        #expect(session.phase == .failed && session.failureDescription != nil)
        session.end()
    }
    @Test func deniedMicrophoneDoesNotLoopOrStartCapture() async throws {
        let input = VoiceInputFixture(), output = VoiceOutputFixture()
        input.prepareError = .microphoneDenied
        let session = VoiceConversationSession(input: input, output: output)
        session.begin(conversationID: UUID(), locale: .init(identifier: "ru-RU")) { _ in Issue.record("Unexpected send"); return "" }
        try await waitUntil { session.phase == .failed }
        #expect(input.prepared == 1 && input.startCount == 0 && output.spoken.isEmpty)
        session.end()
    }
}

@Test @MainActor func audioTapCanRunOffTheMainActorAndRejectsBufferOverflow() async throws {
    let stream = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true))
    let capture = try VoiceAudioCapture(source: format, destination: format, continuation: stream.continuation, activity: {})
    // This callback is constructed by the production factory while called from MainActor.
    let callback = capture.tapBlock()
    try await Task.detached {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true))
        for _ in 0..<5 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            buffer.frameLength = 1024
            memset(buffer.int16ChannelData![0], 0, 1024 * MemoryLayout<Int16>.size)
            callback(buffer, AVAudioTime(sampleTime: 0, atRate: 16000))
        }
    }.value
    do {
        for try await _ in stream.stream {}
        Issue.record("A dropped audio frame must fail instead of silently losing speech")
    } catch { #expect(error as? VoiceFailure == .audioOverrun) }
    capture.finish()
}
