import BlotDesign
import Foundation
import SwiftUI

struct PhoneEmailEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Email")) {
                    TextField(store.t("Your email address"), text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .textContentType(.emailAddress).autocorrectionDisabled().focused($focused)
                    if invalid { Text(store.t("Enter a valid email address.")).font(.footnote).foregroundStyle(.red) }
                }
                WorkspaceFeedback()
            }
            .navigationTitle(store.t("Email")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Save")) { save() }
                }
            }
        }.onAppear { email = store.form.account.email; store.error = nil; focused = true }
    }

    private func save() {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !value.contains(where: { $0.isWhitespace }) else {
            invalid = true; focused = true; return
        }
        store.error = nil
        store.form.account.email = value
        store.persistWorkspace(immediately: true)
        if store.error == nil { dismiss() }
    }
}
