import BlotDesign
import SwiftUI

struct MacSettingsAccountPane: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var signingOut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 42) {
            MacTeamSettingsSection(title: "Основное") {
                MacTeamSettingsRow(title: "Имя") { Text(store.accountDisplayName).foregroundStyle(.secondary).textSelection(.enabled) }
                Divider()
                MacTeamSettingsRow(title: "Электронная почта") { Text(store.form.account.email).foregroundStyle(.secondary).textSelection(.enabled) }
                Divider()
                MacTeamSettingsRow(title: "Пространство") { Text("Личное").foregroundStyle(.secondary) }
                Divider()
                MacTeamSettingsRow(title: "Агенты") { Text(store.snapshot.agents.count, format: .number).foregroundStyle(.secondary) }
                Divider()
                MacTeamSettingsRow(title: "Подключённые аккаунты") { Text(store.snapshot.connections.count, format: .number).foregroundStyle(.secondary) }
            }
            MacTeamSettingsSection(title: "") {
                MacTeamSettingsRow(title: "Сессия", detail: "Выйти из Blot на этом устройстве.") {
                    Button("Выйти", role: .destructive) { signingOut = true }.buttonStyle(MacSettingsActionStyle())
                }
            }
        }.confirmationDialog("Выйти из аккаунта?", isPresented: $signingOut) {
            Button("Выйти", role: .destructive) { store.signOut() }
            Button("Отмена", role: .cancel) { }
        }
    }
}
