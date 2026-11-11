import Foundation
import Observation

/// Owns one foreground conversation. Capture and playback never run together in this prototype.
@MainActor @Observable public final class VoiceConversationSession {
    public enum Phase: Equatable { case idle, preparing, listening, finishing, thinking, speaking, muted, failed }
    public private(set) var phase: Phase = .idle
    public private(set) var conversationID: UUID?
    public private(set) var transcript = ""
    public private(set) var failureDescription: String?
    public private(set) var microphoneMuted = false
    public var isActive: Bool { phase != .idle && phase != .failed }
    @ObservationIgnored private let input: any VoiceRecognizing
    @ObservationIgnored private let output: any VoiceSpeaking
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var listeningSince = Date()
    @ObservationIgnored private var send: (@MainActor (String) async throws -> String)?
    @ObservationIgnored private var locale = Locale(identifier: "ru-RU")
    public init(input: any VoiceRecognizing = AppleVoiceInput(), output: any VoiceSpeaking = AppleVoiceOutput()) {
        self.input = input; self.output = output
    }
    public func begin(conversationID: UUID, locale: Locale, recognitionLocale: Locale? = nil, send: @escaping @MainActor (String) async throws -> String) {
        guard !isActive else { return }
        let previous = operation
        generation = UUID(); let token = generation
        self.conversationID = conversationID; self.locale = locale; self.send = send
        failureDescription = nil; transcript = ""; microphoneMuted = false; phase = .preparing
        operation = Task { [weak self] in
            await previous?.value
            guard let self, self.valid(token) else { return }
            do {
                try self.output.prepare(locale: locale)
                try await self.input.prepare(locale: recognitionLocale ?? locale)
                guard self.valid(token) else { await self.input.stop(); return }
                try await self.listen(token)
            } catch { await self.fail(error, token: token) }
        }
    }
    private func valid(_ token: UUID) -> Bool { generation == token && !Task.isCancelled }
    private func listen(_ token: UUID) async throws {
        guard valid(token) else { return }
        if microphoneMuted { phase = .muted; return }
        transcript = ""; phase = .preparing
        try await input.start(update: { [weak self] text in
            guard let self, self.valid(token), self.phase == .listening else { return }
            if text != self.transcript { self.transcript = text; self.lastActivity = Date() }
        }, activity: { [weak self] in
            guard let self, self.valid(token), self.phase == .listening else { return }; self.lastActivity = Date()
        }, failure: { [weak self] error in
            guard let self, self.generation == token else { return }
            self.operation?.cancel(); self.silence?.cancel(); self.output.stop(); self.phase = .failed
            self.failureDescription = (error as? VoiceFailure)?.localizedDescription ?? VoiceFailure.interrupted.localizedDescription
            self.operation = Task { await self.input.stop() }
        })
        guard valid(token) else { await input.stop(); return }
        lastActivity = Date(); listeningSince = Date(); phase = .listening
        silence?.cancel()
        silence = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.valid(token), self.phase == .listening else { return }
                if !self.transcript.isEmpty, Date().timeIntervalSince(self.lastActivity) >= 0.9 { self.submit(); return }
                if Date().timeIntervalSince(self.listeningSince) >= 60 {
                    if self.transcript.isEmpty { self.toggleMute() } else { self.submit() }
                    return
                }
            }
        }
    }
    public func submit() {
        guard phase == .listening else { return }
        silence?.cancel(); silence = nil
        phase = .finishing
        let token = generation; let previous = operation
        operation = Task { [weak self] in
            await previous?.value
            guard let self, self.valid(token) else { return }
            do {
                let text = try await self.input.finish().trimmingCharacters(in: .whitespacesAndNewlines)
                guard self.valid(token) else { return }
                self.transcript = text
                if text.isEmpty { try await self.listen(token); return }
                guard let send = self.send else { throw VoiceFailure.emptyResponse }
                self.phase = .thinking
                let reply = try await send(text)
                guard self.valid(token) else { return }
                self.phase = .speaking
                try await self.output.speak(VoiceSpokenText.prepare(reply, russian: self.locale.language.languageCode?.identifier == "ru"))
                guard self.valid(token) else { return }
                try await Task.sleep(for: .milliseconds(300))
                try await self.listen(token)
            } catch { await self.fail(error, token: token) }
        }
    }
    public func toggleMute() {
        guard isActive, phase != .preparing, phase != .finishing else { return }
        microphoneMuted.toggle()
        if phase == .listening {
            silence?.cancel(); phase = .muted
            let previous = operation; previous?.cancel()
            operation = Task { [input] in await previous?.value; await input.stop() }
        } else if phase == .muted, !microphoneMuted {
            let previous = operation; let token = generation
            operation = Task { [weak self] in
                await previous?.value
                guard let self, self.valid(token) else { return }
                do { try await self.listen(token) } catch { await self.fail(error, token: token) }
            }
        }
    }
    public func interrupt() {
        guard phase == .speaking else { return }
        let previous = operation; previous?.cancel(); output.stop()
        generation = UUID(); let token = generation; microphoneMuted = false; phase = .preparing
        operation = Task { [weak self] in
            await previous?.value
            guard let self, self.valid(token) else { return }
            do { try await Task.sleep(for: .milliseconds(300)); try await self.listen(token) } catch { await self.fail(error, token: token) }
        }
    }
    public func end() {
        generation = UUID(); silence?.cancel(); silence = nil
        let previous = operation; previous?.cancel(); output.stop()
        send = nil; phase = .idle; conversationID = nil; transcript = ""; failureDescription = nil; microphoneMuted = false
        operation = Task { [input] in await input.stop(); await previous?.value }
    }
    public func audioInterrupted() {
        guard isActive else { return }
        end(); failureDescription = VoiceFailure.interrupted.localizedDescription; phase = .failed
    }
    private func fail(_ error: Error, token: UUID) async {
        guard generation == token, !Task.isCancelled else { return }
        silence?.cancel(); silence = nil; output.stop(); await input.stop()
        guard generation == token else { return }
        failureDescription = (error as? VoiceFailure)?.localizedDescription ?? "Не удалось завершить голосовой запрос. Проверьте сообщения в чате."
        phase = .failed
    }
}
