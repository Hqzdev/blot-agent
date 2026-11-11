import AVFoundation
import BlotAppleIntegrations
import BlotDesign
import SwiftUI

struct WorkspaceVoiceButton: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        Button {
            if store.voice.isActive { store.voice.end() } else { store.beginVoiceConversation() }
        } label: {
            Image(systemName: store.voice.isActive ? "phone.down.fill" : "phone")
                .foregroundStyle(store.voice.isActive ? Color.red : WorkspaceStyle.ink)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(store.language == "ru" ? (store.voice.isActive ? "Завершить разговор" : "Позвонить агенту") : (store.voice.isActive ? "End voice conversation" : "Call agent"))
        .disabled(!store.voice.isActive && (store.mode != .live || store.selectedConversationID == nil || store.isReplying || store.busy || store.route != .chat))
    }
}

struct WorkspaceVoicePanel: View {
    @Environment(WorkspaceStore.self) private var store
    private var voice: VoiceConversationSession { store.voice }
    private var russian: Bool { store.language == "ru" }
    private var title: String {
        if store.appleIntegrations?.interactions.pending != nil, voice.phase == .thinking { return russian ? "Нужно подтверждение на экране" : "Confirm on screen" }
        switch voice.phase {
        case .idle: return ""
        case .preparing: return russian ? "Подготовка микрофона и языка…" : "Preparing microphone and language…"
        case .listening: return russian ? "Слушаю" : "Listening"
        case .finishing: return russian ? "Завершаю распознавание…" : "Finishing transcription…"
        case .thinking: return russian ? "Агент работает…" : "Agent is working…"
        case .speaking: return russian ? "Говорю — микрофон выключен" : "Speaking — microphone is off"
        case .muted: return russian ? "Микрофон выключен" : "Microphone is off"
        case .failed: return russian ? "Разговор остановлен" : "Conversation stopped"
        }
    }
    var body: some View {
        if voice.phase != .idle {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: voice.phase == .listening ? "mic.fill" : "waveform")
                        .foregroundStyle(voice.phase == .listening ? Color.green : WorkspaceStyle.secondary)
                    Text(title).font(.callout.weight(.medium))
                    Spacer(minLength: 4)
                    if voice.phase == .preparing || voice.phase == .finishing || voice.phase == .thinking { ProgressView().controlSize(.small) }
                    Button { voice.end() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).accessibilityLabel(russian ? "Закрыть голосовой режим" : "Close voice mode")
                }
                if let failure = voice.failureDescription { Text(failure).font(.callout).foregroundStyle(WorkspaceStyle.secondary) }
                else if !voice.transcript.isEmpty { Text(voice.transcript).font(.callout).lineLimit(3).textSelection(.enabled) }
                if voice.isActive {
                    HStack(spacing: 12) {
                        Button { voice.toggleMute() } label: {
                            Label(russian ? (voice.microphoneMuted ? "Включить" : "Микрофон") : (voice.microphoneMuted ? "Unmute" : "Microphone"), systemImage: voice.microphoneMuted ? "mic.slash" : "mic")
                        }.disabled(voice.phase == .preparing || voice.phase == .finishing)
                        if voice.phase == .listening {
                            Button(russian ? "Отправить фразу" : "Send phrase") { voice.submit() }
                        }
                        if voice.phase == .speaking { Button(russian ? "Перебить" : "Interrupt") { voice.interrupt() } }
                        Spacer(minLength: 0)
                        Button(role: .destructive) { voice.end() } label: { Image(systemName: "phone.down.fill") }
                            .accessibilityLabel(russian ? "Завершить разговор" : "End conversation")
                    }.font(.callout).buttonStyle(.bordered)
                }
            }
            .padding(12).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
        }
    }
}

struct WorkspaceVoiceLifecycle: ViewModifier {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, value in if value == .background { store.voice.end() } }
            .onDisappear { store.voice.end() }
            .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in store.voice.audioInterrupted() }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { store.voice.audioInterrupted() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue { store.voice.audioInterrupted() }
            }
            #endif
    }
}
