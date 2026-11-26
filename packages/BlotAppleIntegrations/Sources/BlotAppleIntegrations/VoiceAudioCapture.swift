import AVFoundation
import Foundation
import Speech

/// The audio callback owns conversion. No audio buffer is queued on the main actor.
/// The lock protects the bounded stream and converter against stop from the UI thread.
final class VoiceAudioCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let activity: @Sendable () -> Void
    private var closed = false
    private var lastActivity: TimeInterval = 0
    init(source: AVAudioFormat, destination: AVAudioFormat,
         continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation, activity: @escaping @Sendable () -> Void) throws {
        guard let converter = AVAudioConverter(from: source, to: destination) else { throw VoiceFailure.audioUnavailable }
        self.converter = converter; self.format = destination; self.continuation = continuation; self.activity = activity
    }
    nonisolated func tapBlock() -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { [self] buffer, _ in append(buffer) }
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
        guard capacity <= 16384, let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { fail(VoiceFailure.audioUnavailable); return }
        var provided = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, state in
            if provided { state.pointee = .noDataNow; return nil }
            provided = true; state.pointee = .haveData; return buffer
        }
        guard status != .error, error == nil else { fail(VoiceFailure.audioUnavailable); return }
        if converted.frameLength > 0 {
            if case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) { fail(VoiceFailure.audioOverrun) }
        }
        if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var energy: Float = 0
            for index in 0..<Int(buffer.frameLength) { energy += channel[index] * channel[index] }
            let now = ProcessInfo.processInfo.systemUptime
            if sqrt(energy / Float(buffer.frameLength)) > 0.012, now - lastActivity >= 0.1 {
                lastActivity = now; activity()
            }
        }
    }
    private func fail(_ error: Error) { closed = true; continuation.finish(throwing: error) }
    func finish() { lock.lock(); defer { lock.unlock() }; closed = true; continuation.finish() }
}
