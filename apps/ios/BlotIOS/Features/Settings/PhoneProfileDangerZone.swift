import SwiftUI

struct PhoneProfileDangerZone: View {
    private enum Editor: String, Identifiable { case email, password; var id: String { rawValue } }
    private enum Confirmation { case signOut, deleteData }
    @Environment(WorkspaceStore.self) private var store
    @State private var editor: Editor?
    @State private var confirmation: Confirmation?

    var body: some View {
        PhoneSettingsGroup(title: "Danger zone") {
            Button { editor = .email } label: {
                PhoneSettingsRow(title: "Email address", detail: "Profile email on this device; your sign-in address stays unchanged.", value: store.profile.contactEmail ?? store.form.account.email)
            }.buttonStyle(.plain)
            PhoneSettingsDivider()
            Button { editor = .password } label: {
                PhoneSettingsRow(title: "Change password", symbol: "key")
            }.buttonStyle(.plain)
            PhoneSettingsDivider()
            Button { confirmation = .signOut } label: {
                PhoneSettingsRow(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right", showsChevron: false)
            }.buttonStyle(.plain)
            PhoneSettingsDivider()
            Button { confirmation = .deleteData } label: {
                PhoneSettingsRow(title: "Delete data from this iPhone", symbol: "trash", showsChevron: false).foregroundStyle(.red)
            }.buttonStyle(.plain)
            PhoneSettingsDivider()
            WorkspaceAccountDeletionButton()
        }.disabled(store.busy)
        .sheet(item: $editor) { selected in
            switch selected {
            case .email: PhoneEmailEditor().environment(store).presentationDetents([.medium])
            case .password: PhonePasswordEditor().environment(store)
            }
        }
        .confirmationDialog(store.settingsText(confirmation == .deleteData ? "Delete local account data?" : "Sign out?"),
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible, presenting: confirmation) { action in
                Button(store.settingsText(action == .deleteData ? "Delete data from this iPhone" : "Sign out"), role: .destructive) {
                    if action == .deleteData { store.deleteLocalAccount() } else { store.signOut() }
                }
                Button(store.t("Cancel"), role: .cancel) { }
            } message: { action in
                Text(store.settingsText(action == .deleteData
                    ? "This signs you out and removes this account's local workspace and files. Cloud copies and other accounts stay unchanged."
                    : "Sign out of Blot on this device."))
            }
    }
}
