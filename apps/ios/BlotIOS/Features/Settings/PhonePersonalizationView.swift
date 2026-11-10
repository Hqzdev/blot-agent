import BlotDesign
import SwiftUI

struct PhonePersonalizationView: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage(PhoneSettingsPreferenceKey.defaultRole) private var defaultRole = ""
    @AppStorage(PhoneSettingsPreferenceKey.defaultInstructions) private var defaultInstructions = ""
    var body: some View {
        @Bindable var store = store
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "Agent memory") {
                Button { store.navigate(.memory) } label: {
                    PhoneSettingsRow(title: "Saved memories", detail: "Saved information helps your team understand your context.", value: store.snapshot.memories.count.formatted())
                }.buttonStyle(.plain)
            }
            PhoneSettingsGroup(title: "Responses", detail: "Shared response preferences for all agents.") {
                PhoneSettingsValueRow(title: "Communication tone") {
                    options(WorkspacePersonalization.Tone.allCases, title: "Communication tone", selection: $store.form.personalization.tone)
                }
                PhoneSettingsDivider()
                PhoneSettingsValueRow(title: "Answer detail") {
                    options(WorkspacePersonalization.Length.allCases, title: "Answer detail", selection: $store.form.personalization.length)
                }
                PhoneSettingsDivider()
                PhoneSettingsValueRow(title: "Text formatting") {
                    options(WorkspacePersonalization.Format.allCases, title: "Text formatting", selection: $store.form.personalization.format)
                }
            }
            PhoneSettingsGroup(title: "New agents", detail: "Defaults for new specialists. Existing agents keep their instructions.") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.settingsText("Default role")).font(.subheadline)
                    TextField(store.settingsText("Assistant"), text: $defaultRole).textInputAutocapitalization(.sentences)
                        .font(.subheadline).accessibilityLabel(store.settingsText("Default role"))
                }.padding(16)
                PhoneSettingsDivider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.settingsText("Default instructions")).font(.subheadline)
                    TextField(store.settingsText("Default instructions"), text: $defaultInstructions, axis: .vertical)
                        .lineLimit(4...10).font(.subheadline)
                }.padding(16)
            }
            WorkspaceFeedback()
        }
        .onChange(of: store.form.personalization) { _, _ in store.persistChatState() }
    }
    private func options<Value>(_ values: [Value], title: String, selection: Binding<Value>) -> some View
    where Value: RawRepresentable & Identifiable & Hashable, Value.RawValue == String {
        Picker(store.settingsText(title), selection: selection) {
            ForEach(values) { value in Text(store.t(value.rawValue)).tag(value) }
        }.labelsHidden()
    }
}
