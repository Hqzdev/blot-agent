import SwiftUI

struct WorkspaceAccountDeletionButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var presented = false
    var body: some View {
        Button(store.language == "ru" ? "Удалить аккаунт и облачные данные" : "Delete account and cloud data", role: .destructive) { presented = true }
            .disabled(store.accountDeletion == nil || store.busy)
            .sheet(isPresented: $presented) { WorkspaceAccountDeletionView().environment(store) }
    }
}
private struct WorkspaceAccountDeletionView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        NavigationStack {
            Form {
                Text(ru ? "Аккаунт, облачные копии, сеансы и локальные файлы этого аккаунта будут удалены. Восстановить их будет нельзя. Копии на других отключённых устройствах нельзя стереть удалённо." : "Your account, cloud backups, sessions and this account's local files will be deleted permanently. Offline copies on other devices cannot be erased remotely.")
                Button(ru ? "Отправить код на почту аккаунта" : "Send code to account email") { perform { try await $0.requestAccountDeletion(); sent = true } }
                if sent {
                    TextField(ru ? "Код из письма" : "Email code", text: $code).textFieldStyle(.roundedBorder)
                    Button(ru ? "Удалить аккаунт навсегда" : "Permanently delete account", role: .destructive) {
                        perform { try await $0.confirmAccountDeletion(code: code); dismiss(); store.signOut() }
                    }.disabled(code.count != 6)
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.formStyle(.grouped).disabled(busy)
            .navigationTitle(ru ? "Удаление аккаунта" : "Delete account")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("Cancel")) { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
        #if os(macOS)
        .frame(width: 520, height: 420)
        #endif
    }
    private func perform(_ action: @escaping @MainActor (any WorkspaceAccountDeleting) async throws -> Void) {
        guard !busy, let service = store.accountDeletion else { return }; busy = true; failure = nil
        _Concurrency.Task {
            defer { busy = false }
            do { try await action(service) }
            catch WorkspaceAccountDeletionFailure.localCleanupIncomplete {
                dismiss(); store.signOut()
                store.error = ru ? "Аккаунт удалён в облаке. Локальная очистка не завершена; повторите запуск приложения." : "The cloud account was deleted. Local cleanup is incomplete; restart the app."
            }
            catch { failure = ru ? "Удаление не подтверждено. Проверьте код и подключение." : "Deletion could not be confirmed. Check the code and connection." }
        }
    }
}
