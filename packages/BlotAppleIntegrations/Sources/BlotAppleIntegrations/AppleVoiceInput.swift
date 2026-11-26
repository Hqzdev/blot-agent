import AVFoundation
import Foundation
import Speech

@MainActor public final class AppleVoiceInput: VoiceRecognizing {
    private enum Kind { case speech, dictation }
    private var kind: Kind?
    private var locale = Locale(identifier: "ru-RU")
    private var engine: AVAudioEngine?
    private var capture: VoiceAudioCapture?
    private var analyzer: SpeechAnalyzer?
    private var results: Task<Void, Error>?
    private var transcript = VoiceTranscript()
    public init() {}
    /// Capability lookup only: no microphone permission or model downloads.
    public static func supportedLocales() async -> [Locale] {
        var identifiers = Set<String>()
        if SpeechTranscriber.isAvailable {
            for locale in await SpeechTranscriber.supportedLocales { identifiers.insert(locale.identifier.replacingOccurrences(of: "_", with: "-")) }
        }
        for locale in await DictationTranscriber.supportedLocales { identifiers.insert(locale.identifier.replacingOccurrences(of: "_", with: "-")) }
        return identifiers.sorted().map(Locale.init(identifier:))
    }
    public func prepare(locale: Locale) async throws {
        self.locale = locale
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            kind = .speech; self.locale = supported
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            kind = .dictation; self.locale = supported
        } else { throw VoiceFailure.languageUnavailable }
        let module = try module()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
        try Task.checkCancellation()
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
        default: allowed = false
        }
        guard allowed else { throw VoiceFailure.microphoneDenied }
    }
    private func module() throws -> any SpeechModule {
        switch kind {
        case .speech: SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        case .dictation: DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        case nil: throw VoiceFailure.languageUnavailable
        }
    }
    public func start(update: @escaping @MainActor (String) -> Void, activity: @escaping @MainActor () -> Void,
                      failure: @escaping @MainActor (Error) -> Void) async throws {
        await stop()
        try Task.checkCancellation()
        try Self.activateAudio()
        let module = try module()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw VoiceFailure.audioUnavailable }
        let analyzer = SpeechAnalyzer(modules: [module]); self.analyzer = analyzer
        transcript = VoiceTranscript()
        if let speech = module as? SpeechTranscriber {
            results = Task { [weak self] in
                do {
                    for try await result in speech.results {
                        try Task.checkCancellation()
                        self?.accept(String(result.text.characters), start: result.range.start.seconds, end: result.range.end.seconds, update: update)
                    }
                } catch { if !Task.isCancelled { failure(error) }; throw error }
            }
        } else if let dictation = module as? DictationTranscriber {
            results = Task { [weak self] in
                do {
                    for try await result in dictation.results {
                        try Task.checkCancellation()
                        self?.accept(String(result.text.characters), start: result.range.start.seconds, end: result.range.end.seconds, update: update)
                    }
                } catch { if !Task.isCancelled { failure(error) }; throw error }
            }
        }
        do {
            let stream = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(16))
            let engine = AVAudioEngine(); self.engine = engine
            let input = engine.inputNode
            let natural = input.outputFormat(forBus: 0)
            guard natural.sampleRate > 0, natural.channelCount > 0 else { throw VoiceFailure.audioUnavailable }
            let capture = try VoiceAudioCapture(source: natural, destination: format, continuation: stream.continuation,
                activity: { Task { @MainActor in activity() } })
            self.capture = capture
            input.installTap(onBus: 0, bufferSize: 2048, format: natural, block: capture.tapBlock())
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream.stream)
            try Task.checkCancellation()
            engine.prepare(); try engine.start()
        } catch { await stop(); throw error }
    }
    private func accept(_ text: String, start: Double, end: Double, update: (String) -> Void) {
        transcript.replace(start: start, end: end, text: text); update(transcript.text)
    }
    private func stopCapture() {
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil; capture?.finish(); capture = nil
    }
    public func finish() async throws -> String {
        stopCapture()
        guard let analyzer else { return transcript.text }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await analyzer.finalizeAndFinishThroughEndOfInput() }
                group.addTask { try await Task.sleep(for: .seconds(4)); await analyzer.cancelAndFinishNow(); throw VoiceFailure.interrupted }
                _ = try await group.next(); group.cancelAll()
            }
            try await results?.value
            self.analyzer = nil; results = nil
            return transcript.text
        } catch { await stop(); throw error }
    }
    public func stop() async {
        stopCapture()
        results?.cancel(); let old = analyzer; analyzer = nil
        await old?.cancelAndFinishNow()
        if let results { _ = try? await results.value }
        results = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    static func activateAudio() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        #endif
    }
}
