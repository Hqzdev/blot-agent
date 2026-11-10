import BlotDesign
import SwiftUI

struct MacSettingsPersonalizationPane: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage(MacTeamPreferenceKey.defaultRole) private var defaultRole = "Ассистент"
    @AppStorage(MacTeamPreferenceKey.defaultInstructions) private var defaultInstructions = ""
    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 42) {
            MacTeamSettingsSection(title: "Память агентов", detail: "Сохранённые сведения, которые помогают команде учитывать ваш контекст.") {
                MacTeamSettingsLink(title: "Сохранённые воспоминания", detail: "Записей: \(store.snapshot.memories.count)", actionTitle: "Управлять") {
                    store.settingsRoute = .memory
                }
            }
            MacTeamSettingsSection(title: "Ответы", detail: "Общие предпочтения стиля для всех агентов.") {
                MacTeamSettingsRow(title: "Тон общения") {
                    MacTeamSelect(title: "Тон общения", selection: $store.form.personalization.tone,
                        options: WorkspacePersonalization.Tone.allCases.map { .init(store.t($0.rawValue), $0) }, showsTitle: false)
                }
                Divider()
                MacTeamSettingsRow(title: "Подробность ответа") {
                    MacTeamSelect(title: "Подробность ответа", selection: $store.form.personalization.length,
                        options: WorkspacePersonalization.Length.allCases.map { .init(store.t($0.rawValue), $0) }, showsTitle: false)
                }
                Divider()
                MacTeamSettingsRow(title: "Оформление текста") {
                    MacTeamSelect(title: "Оформление текста", selection: $store.form.personalization.format,
                        options: WorkspacePersonalization.Format.allCases.map { .init(store.t($0.rawValue), $0) }, showsTitle: false)
                }
            }
            MacTeamSettingsSection(title: "Новые агенты", detail: "Готовые настройки для создания специалиста. Существующие агенты сохраняют свои инструкции.") {
                MacTeamSettingsRow(title: "Роль по умолчанию") {
                    TextField("Ассистент", text: $defaultRole).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .frame(width: 200).accessibilityLabel("Роль по умолчанию")
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Инструкции по умолчанию")
                    TextEditor(text: $defaultInstructions).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .frame(height: 110).padding(10).background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Инструкции по умолчанию")
                }.padding(.vertical, 16)
            }
        }.onChange(of: store.form.personalization) { _, _ in store.persistChatState() }
    }
}
