import BlotDesign
import SwiftUI

struct PhonePersonalizationView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 28) {
                Text(store.t("Applies to new replies from every agent. Individual agent roles stay unchanged."))
                    .font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PhoneSettingsGroup(title: "Character") {
                    options(WorkspacePersonalization.Tone.allCases, selection: $store.form.personalization.tone)
                }
                PhoneSettingsGroup(title: "Answer length") {
                    options(WorkspacePersonalization.Length.allCases, selection: $store.form.personalization.length)
                }
                PhoneSettingsGroup(title: "Formatting") {
                    options(WorkspacePersonalization.Format.allCases, selection: $store.form.personalization.format)
                }
                Text(store.t("Changes are saved automatically."))
                    .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                if store.mode == .live { WorkspaceLink(title: "Memory", route: .memory, symbol: "brain") }
                WorkspaceFeedback()
            }.padding(20)
        }.background(PhoneSettingsStyle.canvas.ignoresSafeArea())
    }

    private func options<Value>(_ values: [Value], selection: Binding<Value>) -> some View
    where Value: RawRepresentable & Identifiable & Equatable, Value.RawValue == String {
        ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
            if index > 0 { PhoneSettingsDivider() }
            Button { selection.wrappedValue = value } label: {
                HStack(spacing: 16) {
                    Text(store.t(value.rawValue)).font(.body)
                    Spacer(minLength: 8)
                    if value == selection.wrappedValue { BlotIcon(.checkCircle).foregroundStyle(WorkspaceStyle.ink) }
                    else { Circle().strokeBorder(WorkspaceStyle.secondary.opacity(0.25), lineWidth: 1.5).frame(width: 20, height: 20) }
                }.padding(.horizontal, 18).frame(minHeight: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(value == selection.wrappedValue ? .isSelected : [])
        }
    }
}
