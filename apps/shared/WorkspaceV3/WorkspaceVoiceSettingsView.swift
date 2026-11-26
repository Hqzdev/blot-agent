import BlotAppleIntegrations
import SwiftUI

struct WorkspaceVoiceSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var locales: [Locale] = []
    @State private var loaded = false
    private var russian: Bool { store.language == "ru" }
    private var title: String { russian ? "Голосовой режим" : "Voice mode" }
    private var detail: String {
        russian ? "Выберите язык, на котором говорите. Он используется для расшифровки со следующего звонка. Язык интерфейса не изменится." : "Choose the language you speak. It is used for transcription from your next call. The interface language stays the same."
    }
    private var displayLocale: Locale { Locale(identifier: store.language) }
    private func name(_ id: String) -> String { displayLocale.localizedString(forIdentifier: id) ?? id }
    private var languageIDs: [String] { locales.map { $0.identifier.replacingOccurrences(of: "_", with: "-") } }
    var body: some View {
        Group {
            #if os(macOS)
            MacTeamSettingsSection(title: title) {
                MacTeamSettingsRow(localizesTitle: false, title: russian ? "Язык распознавания" : "Recognition language", detail: detail) {
                    picker
                }
                availability
            }
            #else
            PhoneSettingsGroup(title: title) {
                PhoneSettingsValueRow(title: russian ? "Язык распознавания" : "Recognition language", detail: detail) {
                    picker
                }
                availability.padding(.horizontal, 16).padding(.bottom, loaded && locales.isEmpty ? 12 : 0)
            }
            #endif
        }
        .task {
            let available = await AppleVoiceInput.supportedLocales()
            guard !_Concurrency.Task.isCancelled else { return }
            locales = available; loaded = true
        }
    }
    private var picker: some View {
        @Bindable var preferences = store.voicePreferences
        let fallback = WorkspaceVoicePreferences.followInterface
        var options: [WorkspaceChoiceOption<String>] = [.init(fallback, russian ? "Как в приложении" : "Same as app")]
        if preferences.selection != fallback, !languageIDs.contains(preferences.selection) {
            options.append(.init(preferences.selection, name(preferences.selection) + (loaded ? (russian ? " — недоступен" : " — unavailable") : "")))
        }
        options += languageIDs.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }.map { .init($0, name($0)) }
        return WorkspaceChoice(title: russian ? "Язык распознавания" : "Recognition language", selection: $preferences.selection, options: options, showsTitle: false)
        .accessibilityLabel(russian ? "Язык распознавания речи" : "Speech recognition language")
        .accessibilityIdentifier("workspace.voice.recognition-language")
    }
    @ViewBuilder private var availability: some View {
        if !loaded { ProgressView().controlSize(.small).accessibilityLabel(russian ? "Проверка доступных языков" : "Checking available languages") }
        else if locales.isEmpty {
            Text(russian ? "На этом устройстве локальное распознавание недоступно." : "On-device speech recognition is unavailable on this device.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
