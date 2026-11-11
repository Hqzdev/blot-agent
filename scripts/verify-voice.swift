import AppKit
import AVFoundation
import BlotAppleIntegrations
import Foundation
import Speech
import SwiftUI

@MainActor private func diagnostic(_ value: String) {
    print(value)
    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let url = cache.appendingPathComponent("VoiceVerification.log")
    var data = (try? Data(contentsOf: url)) ?? Data()
    if data.count > 64 * 1024 { data = Data() }
    data.append(Data((value + "\n").utf8)); try? data.write(to: url, options: .atomic)
}

@MainActor private func roundTrip() async throws {
    diagnostic("CHECK: Russian locale and voice")
    let locale = Locale(identifier: "ru-RU")
    guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale),
          AVSpeechSynthesisVoice(language: "ru-RU") != nil else { throw VoiceFailure.languageUnavailable }
    let transcriber = DictationTranscriber(locale: supported, preset: .longDictation)
    // Verification never downloads a model implicitly.
    guard await DictationTranscriber.installedLocales.contains(supported) else { throw VoiceFailure.languageUnavailable }
    guard let url = Bundle.main.url(forResource: "RussianFixture", withExtension: "aiff") else { throw VoiceFailure.audioUnavailable }
    diagnostic("CHECK: recognize generated system-voice fixture")
    let input = try AVAudioFile(forReading: url)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let transcript = Task { @MainActor in
        var value = VoiceTranscript()
        for try await result in transcriber.results {
            value.replace(start: result.range.start.seconds, end: result.range.end.seconds, text: String(result.text.characters))
        }
        return value.text
    }
    do {
        try await analyzer.start(inputAudioFile: input, finishAfterFile: true)
        let text = try await transcript.value
        guard text.localizedCaseInsensitiveContains("проверка"), text.localizedCaseInsensitiveContains("папку") else { throw VoiceFailure.emptyResponse }
        diagnostic("PASS: actual Russian system voice → PCM file → local DictationTranscriber: \(text)")
        let output = AppleVoiceOutput(); try output.prepare(locale: locale)
        try await output.speak("Проверка завершена. Голосовой режим работает.")
        diagnostic("PASS: production AppleVoiceOutput playback completed")
    } catch { await analyzer.cancelAndFinishNow(); transcript.cancel(); throw error }
}

@MainActor private func captureSmoke() async throws {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw VoiceFailure.microphoneDenied }
    let input = AppleVoiceInput()
    try await input.prepare(locale: Locale(identifier: "ru-RU"))
    for cycle in 1...3 {
        try await input.start(update: { _ in }, activity: {}, failure: { error in diagnostic("FAIL: capture callback: \(error)") })
        try await Task.sleep(for: .seconds(2))
        await input.stop()
        diagnostic("PASS: real microphone start/stop cycle \(cycle)")
    }
}

private struct VoiceProbeView: View {
    @State private var voice = VoiceConversationSession()
    @State private var replies = 0
    private let id = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Blot — проверка голоса").font(.title2.bold())
            Text("Изолированная проверка микрофона и русского голоса. Произнесённый текст не отправляется в ИИ и не записывается в аккаунт.")
                .foregroundStyle(.secondary)
            Text(String(describing: voice.phase)).font(.headline)
            Text(voice.failureDescription ?? (voice.transcript.isEmpty ? "Нажмите «Начать» и произнесите короткую фразу." : voice.transcript))
                .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading).textSelection(.enabled)
            HStack {
                Button("Начать") {
                    voice.begin(conversationID: id, locale: Locale(identifier: "ru-RU")) { text in
                        replies += 1
                        diagnostic("PASS: microphone → finalized transcript (characters=\(text.count)), turn=\(replies)")
                        return "Я услышал: \(text)"
                    }
                }.disabled(voice.isActive)
                Button("Отправить фразу") { voice.submit() }.disabled(voice.phase != .listening)
                Button("Перебить") { voice.interrupt() }.disabled(voice.phase != .speaking)
                Button("Завершить") { voice.end(); diagnostic("STOP: voice conversation ended by owner") }
            }.buttonStyle(.bordered)
            Text("После ответа микрофон включится снова. Во время озвучки он выключен.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 640)
            .onDisappear { voice.end() }
    }
}

@MainActor @main private enum VoiceVerification {
    private static var window: NSWindow?
    static func main() {
        setbuf(stdout, nil)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: cache.appendingPathComponent("VoiceVerification.log"))
        let application = NSApplication.shared
        let smoke = CommandLine.arguments.contains("--capture-smoke")
        let automated = smoke || CommandLine.arguments.contains("--self-test")
        application.setActivationPolicy(automated ? .accessory : .regular)
        if automated {
            Task {
                do {
                    if smoke { try await captureSmoke(); diagnostic("PASS: real microphone verification completed") }
                    else { try await roundTrip(); diagnostic("PASS: native voice round trip completed") }
                    exit(0)
                }
                catch { diagnostic("FAIL: \(error)"); exit(1) }
            }
            Task { try? await Task.sleep(for: .seconds(35)); diagnostic("FAIL: native voice verification timed out"); exit(2) }
        } else {
            let value = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 640, height: 360), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            value.title = "Blot — проверка голоса"
            value.contentView = NSHostingView(rootView: VoiceProbeView())
            window = value; value.makeKeyAndOrderFront(nil); application.activate(ignoringOtherApps: true)
        }
        application.run()
    }
}
