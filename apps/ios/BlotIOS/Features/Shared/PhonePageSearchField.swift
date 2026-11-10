import BlotDesign
import SwiftUI

struct PhonePageSearchField: View {
    let placeholder: String
    @Binding var text: String
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            BlotIcon(.search, size: 18).foregroundStyle(WorkspaceStyle.secondary)
            TextField(placeholder, text: $text).font(.subheadline).textFieldStyle(.plain)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .submitLabel(.search).accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    BlotIcon(symbol: "xmark.circle.fill", size: 18)
                        .frame(width: 44, height: 44).foregroundStyle(WorkspaceStyle.secondary)
                }.buttonStyle(.plain).accessibilityLabel(store.t("Clear search"))
            }
        }
        .padding(.leading, 16).padding(.trailing, text.isEmpty ? 16 : 2).frame(minHeight: 48)
        .background(PhoneSettingsStyle.row, in: RoundedRectangle(cornerRadius: PhonePageLayout.radius))
        .overlay(RoundedRectangle(cornerRadius: PhonePageLayout.radius).strokeBorder(PhoneSettingsStyle.edge))
    }
}
