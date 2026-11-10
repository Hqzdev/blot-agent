import SwiftUI

struct PhonePasswordEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var codeSent = false
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            PhoneSettingsPage {
                PhoneSettingsGroup(title: "Change password", detail: "We will send a verification code to your sign-in email.") {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(store.signInEmail).font(.subheadline).textSelection(.enabled)
                        if codeSent {
                            TextField(store.settingsText("Verification code"), text: $code)
                                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            SecureField(store.t("New password"), text: $password).textContentType(.newPassword)
                            SecureField(store.settingsText("Repeat new password"), text: $confirmation).textContentType(.newPassword)
                            Text(store.settingsText("Changing your password signs you out. Sign in again with the new password."))
                                .font(.footnote).foregroundStyle(.secondary)
                            Button(store.t("Save")) { submitPassword() }.buttonStyle(.borderedProminent)
                                .disabled(password.count < 8 || password != confirmation || code.count != 6)
                        } else {
                            Button(store.settingsText("Send verification code")) { requestCode() }.buttonStyle(.borderedProminent)
                        }
                        if submitting { ProgressView() }
                    }.padding(16).textFieldStyle(.roundedBorder)
                }
                WorkspaceFeedback()
            }.disabled(submitting)
            .safeAreaInset(edge: .top, spacing: 0) {
                PhonePageHeader(title: store.settingsText("Change password"), back: { dismiss() }).disabled(submitting)
            }
            .toolbar(.hidden, for: .navigationBar)
        }.interactiveDismissDisabled(submitting)
    }
    private func requestCode() {
        submitting = true
        Task {
            defer { submitting = false }
            if await store.requestPasswordChangeCode() { codeSent = true }
        }
    }
    private func submitPassword() {
        submitting = true
        Task {
            defer { submitting = false }
            if await store.changeAccountPassword(code: code, password: password) { dismiss() }
        }
    }
}
