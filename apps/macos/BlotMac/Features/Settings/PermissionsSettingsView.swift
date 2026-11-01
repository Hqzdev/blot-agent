import BlotAPI
import BlotDesign
import SwiftUI

/// «07 · Settings — Permissions»: how approvals work and every action waiting for one.
struct PermissionsSettingsView: View {
    @Environment(AppState.self) private var app
    @Bindable var settings: SettingsState
    var body: some View {
        let actions = app.workspace.rows("PREPARED_ACTION").filter {
            ["PREPARED", "EXECUTING"].contains($0.data.text("status"))
        }
        SettingsGroup(title: "Approvals") {
            SettingsRow(title: "Ask before running",
                        detail: "A permission covers one exact action, its base commit, five minutes and a single use. Agents cannot grant permissions to themselves.") {
                StatusBadge("Always on", tone: .success)
            }
        }
        SettingsGroup(title: "Waiting for approval", detail: actions.isEmpty ? nil : "\(actions.count) actions") {
            if actions.isEmpty {
                EmptyState(icon: "shield-check", title: "Nothing to approve",
                           detail: "Commands, file changes, commits and pushes appear here when an agent prepares them.")
            }
        }
        ForEach(actions, id: \.id) { PreparedActionView(action: $0).transition(.kAppear) }
    }
}
