import BlotDesign
import Foundation
import SwiftUI

struct PhoneEmailEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var invalid = false
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            PhoneSettingsPage {
                PhoneSettingsGroup(title: "Email") {
                    VStack(alignment: .leading, spacing: 12) {
                    TextField(store.t("Your email address"), text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .textContentType(.emailAddress).autocorrectionDisabled().focused($focused)
                    if invalid { Text(store.t("Enter a valid email address.")).font(.footnote).foregroundStyle(.red) }
                    }.padding(PhonePageLayout.rowInset)
                }
                WorkspaceFeedback()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                PhonePageHeader(title: store.t("Email"), back: { dismiss() }) {
                    Button(store.t("Save")) { save() }.frame(minWidth: 44, minHeight: 44)
                }
                .disabled(saving)
            }.toolbar(.hidden, for: .navigationBar)
        }.interactiveDismissDisabled(saving)
        .onAppear { email = store.profile.contactEmail ?? store.form.account.email; store.error = nil; focused = true }
    }

    private func save() {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !value.contains(where: { $0.isWhitespace }) else {
            invalid = true; focused = true; return
        }
        saving = true
        var profile = store.profile
        profile.contactEmail = value
        Task {
            defer { saving = false }
            if await store.saveProfile(profile) { dismiss() }
        }
    }
}
