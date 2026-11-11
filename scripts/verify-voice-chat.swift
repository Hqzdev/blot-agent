import AppKit
import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation
@testable import Blot

@MainActor private final class ChatVoiceInput: VoiceRecognizing {
    var active = false
    var phrase = "Привет"
    var preparedLocale: Locale?
    func prepare(locale: Locale) async throws { preparedLocale = locale }
    func start(update: @escaping @MainActor (String) -> Void, activity: @escaping @MainActor () -> Void, failure: @escaping @MainActor (Error) -> Void) async throws { active = true }
    func finish() async throws -> String { active = false; return phrase }
    func stop() async { active = false }
}
@MainActor private final class ChatVoiceOutput: VoiceSpeaking {
    var spoken: [String] = []
    var preparedLocale: Locale?
    func prepare(locale: Locale) throws { preparedLocale = locale }
    func speak(_ text: String) async throws { spoken.append(text) }
    func stop() {}
}
private struct ChatVoiceModel: ChatModel {
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.text("Проверка голосового чата завершена."))
            continuation.yield(.finished(.stop)); continuation.finish()
        }
    }
}
@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<300 {
        if condition() { return }
        try await _Concurrency.Task.sleep(for: .milliseconds(20))
    }
    throw VoiceFailure.emptyResponse
}

@MainActor @main private enum VoiceChatVerification {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("blot-voice-chat-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalWorkspaceService(databaseURL: root.appendingPathComponent("workspace.sqlite"), makeModel: { _ in ChatVoiceModel() })
        let input = ChatVoiceInput(), output = ChatVoiceOutput()
        let voice = VoiceConversationSession(input: input, output: output)
        let suite = "dev.blot.voice-preferences-fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WorkspaceVoicePreferences(defaults: defaults)
        guard preferences.selection == WorkspaceVoicePreferences.followInterface,
              preferences.recognitionLocale(interfaceLanguage: "ru").identifier == "ru-RU",
              preferences.recognitionLocale(interfaceLanguage: "en").identifier == "en-US" else { throw VoiceFailure.languageUnavailable }
        preferences.selection = "fr-FR"
        guard WorkspaceVoicePreferences(defaults: defaults).selection == "fr-FR" else { throw VoiceFailure.languageUnavailable }
        let store = WorkspaceStore(mode: .live, service: local, voice: voice, voicePreferences: preferences)
        await store.loadWorkspace()
        store.form.agent = WorkspaceAgentForm(name: "Voice fixture", instructions: "Answer briefly")
        await store.perform(.createAgent)
        guard let agentID = store.selectedAgentID else { throw VoiceFailure.emptyResponse }
        await store.newChat(with: agentID)
        guard let directID = store.selectedConversationID else { throw VoiceFailure.emptyResponse }
        try await checkTurn(store: store, input: input, output: output, conversationID: directID)
        guard input.preparedLocale?.identifier == "fr-FR",
              output.preparedLocale?.identifier == (store.language == "ru" ? "ru-RU" : "en-US") else { throw VoiceFailure.languageUnavailable }
        print("PASS: persisted recognition language reaches the input adapter without changing playback/interface language")
        print("PASS: voice → actual WorkspaceStore → durable personal chat → model → speech, typed draft preserved")
        preferences.selection = "de-DE"
        let created = await store.createGroup(title: "Voice group fixture", agentIDs: [agentID])
        guard created, let groupID = store.selectedConversationID else { throw VoiceFailure.emptyResponse }
        try await checkTurn(store: store, input: input, output: output, conversationID: groupID)
        guard input.preparedLocale?.identifier == "de-DE" else { throw VoiceFailure.languageUnavailable }
        print("PASS: changing recognition language applies to the next group call")
        print("PASS: voice → actual group conversation routing → final reply → one speech output")
        store.beginVoiceConversation()
        try await waitUntil { voice.phase == .listening }
        store.navigate(.files)
        try await waitUntil { !input.active }
        guard voice.phase == .idle else { throw VoiceFailure.interrupted }
        print("PASS: leaving the chat releases voice input")
        try await local.close()
    }
    private static func checkTurn(store: WorkspaceStore, input: ChatVoiceInput, output: ChatVoiceOutput, conversationID: UUID) async throws {
        store.form.composer.draft = "Unsent keyboard draft"
        let before = output.spoken.count
        store.beginVoiceConversation()
        try await waitUntil { store.voice.phase == .listening }
        store.voice.submit(); store.voice.submit()
        try await waitUntil { output.spoken.count == before + 1 && store.voice.phase == .listening }
        guard output.spoken.last == "Проверка голосового чата завершена.",
              store.form.composer.draft == "Unsent keyboard draft",
              store.snapshot.messages.filter({ $0.conversationId == conversationID && $0.role == .user }).count == 1,
              store.snapshot.messages.contains(where: { $0.conversationId == conversationID && $0.role == .assistant && $0.delivery == .completed && $0.content == output.spoken.last }) else { throw VoiceFailure.emptyResponse }
        store.voice.end(); try await waitUntil { !input.active }
    }
}
