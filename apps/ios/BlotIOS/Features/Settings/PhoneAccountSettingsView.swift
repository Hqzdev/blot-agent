import BlotDesign
import SwiftUI

struct PhoneAccountSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var editingEmail = false
    @State private var deletingAccount = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                PhoneSettingsGroup(title: "Account") {
                    Button { editingEmail = true } label: {
                        PhoneSettingsRow(title: "Email", symbol: "envelope",
                            detail: store.form.account.email.isEmpty ? store.t("Not specified") : store.form.account.email)
                    }.buttonStyle(.plain)
                    PhoneSettingsDivider()
                    PhoneSettingsRow(title: "Sign-in method", symbol: "lock",
                        value: store.t("Email"), showsChevron: false)
                }
                PhoneSettingsGroup(title: "Privacy and access") {
                    Button { store.navigate(.permissions) } label: {
                        PhoneSettingsRow(title: "Access and permissions", symbol: "checkmark.shield")
                    }.buttonStyle(.plain)
                }
                Button(role: .destructive) { deletingAccount = true } label: {
                    PhoneSettingsRow(title: "Delete account", symbol: "xmark.circle", showsChevron: false).foregroundStyle(.red)
                }
                .buttonStyle(.plain).background(PhoneSettingsStyle.row, in: RoundedRectangle(cornerRadius: 28))
                WorkspaceFeedback()
            }.padding(20)
        }
        .background(PhoneSettingsStyle.canvas.ignoresSafeArea())
        .sheet(isPresented: $editingEmail) { PhoneEmailEditor().environment(store).presentationDetents([.medium]) }
        .confirmationDialog(store.t("Delete local account data?"), isPresented: $deletingAccount, titleVisibility: .visible) {
            Button(store.t("Delete account"), role: .destructive) { store.deleteLocalAccount() }
            Button(store.t("Cancel"), role: .cancel) { }
        } message: { Text(store.t("This removes this workspace and its files from this iPhone.")) }
    }
}
