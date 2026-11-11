import AVFoundation
import Foundation

@MainActor public final class AppleVoiceOutput: NSObject, VoiceSpeaking, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var completion: CheckedContinuation<Void, Error>?
    private var utterance: AVSpeechUtterance?
    private var watchdog: Task<Void, Never>?
    public override init() { super.init(); synthesizer.delegate = self }
    public func prepare(locale: Locale) throws {
        voice = AVSpeechSynthesisVoice(language: locale.identifier.replacingOccurrences(of: "_", with: "-"))
        guard voice != nil else { throw VoiceFailure.voiceUnavailable }
    }
    public func speak(_ text: String) async throws {
        try Task.checkCancellation()
        guard let voice else { throw VoiceFailure.voiceUnavailable }
        stop()
        try AppleVoiceInput.activateAudio()
        let item = AVSpeechUtterance(string: text); item.voice = voice
        item.rate = AVSpeechUtteranceDefaultSpeechRate
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                utterance = item; completion = continuation; synthesizer.speak(item)
                watchdog = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15 + Double(text.count) / 4)) } catch { return }
                    guard let self, self.utterance === item else { return }
                    self.utterance = nil; let reply = self.completion; self.completion = nil
                    self.synthesizer.stopSpeaking(at: .immediate); reply?.resume(throwing: VoiceFailure.audioUnavailable)
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stop() } }
    }
    public func stop() {
        watchdog?.cancel(); watchdog = nil
        utterance = nil
        let reply = completion; completion = nil
        synthesizer.stopSpeaking(at: .immediate)
        reply?.resume(throwing: CancellationError())
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
    private func finished(_ id: ObjectIdentifier) {
        guard utterance.map(ObjectIdentifier.init) == id else { return }
        watchdog?.cancel(); watchdog = nil
        utterance = nil; let reply = completion; completion = nil; reply?.resume()
    }
}
