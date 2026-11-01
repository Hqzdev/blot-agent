import BlotAPI
import BlotDesign
import SwiftUI

/// «12 · Automations» detail: header with status and Run now, trigger, instructions and run history.
struct AutomationDetailView: View {
    @Environment(AppState.self) private var app
    let item: WorkspaceRow
    @State private var editing = false
    @State private var deleting = false
    @State private var running = false

    private var enabled: Bool { item.data.flag("enabled") }
    private var busy: Bool { !app.workspace.commands.active.isEmpty }
    private var history: [WorkspaceRow] {
        Array(app.workspace.rows("CHECKPOINT", parentID: item.id).filter { $0.data.text("phase") == "automation_run" }.reversed())
    }
    private var nextRun: String? {
        guard enabled, let next = WorkspaceDate.parse(item.data.text("nextAt")) else { return nil }
        return "Next run " + next.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.section) {
            PageHeader(icon: "clock", title: item.data.text("name"),
                       subtitle: nextRun ?? (enabled ? "Waiting for the next scheduled day" : "Paused — it will not start on its own")) {
                StatusBadge(enabled ? "Active" : "Paused", tone: enabled ? .success : .neutral)
            } actions: {
                KButton(title: "Run now", icon: "play", loading: running) { runNow() }
                    .disabled(busy)
                MoreMenu(help: "Schedule actions") {[
                    .button("Edit…", icon: "pencil") { editing = true },
                    .button(enabled ? "Pause schedule" : "Turn on schedule", icon: enabled ? "pause" : "play") {
                        app.setAutomation(item, enabled: !enabled)
                    },
                    .divider,
                    .button("Delete…", icon: "trash-2", destructive: true) { deleting = true },
                ]}
            }

            SettingsGroup(title: "Trigger") {
                SettingsRow(title: "Schedule", detail: "Times use the \(item.data.text("timezone")) time zone. After sleep, missed runs are merged into one.") {
                    Chip(icon: "clock", label: AutomationSchedule.describe(item), chevron: false, bordered: true)
                }
                SettingsDivider()
                SettingsRow(title: "Project", detail: "Blot works in a fresh workspace of this project.") {
                    Chip(icon: "folder", label: app.workspace.find("PROJECT", item.projectId)?.data.text("name") ?? "Unavailable",
                         chevron: false, bordered: true)
                }
                SettingsDivider()
                SettingsRow(title: "Token budget", detail: "Maximum each run may spend.") {
                    Text("\(item.data.integer("tokenBudget").formatted()) tokens").font(KFont.mono(12)).foregroundStyle(K.text2)
                }
                SettingsDivider()
                SettingsRow(title: "Run on schedule", detail: "Each run goes through the usual planning and approvals, like any task.") {
                    KToggle(isOn: Binding(get: { enabled }, set: { app.setAutomation(item, enabled: $0) }))
                        .accessibilityLabel("Schedule enabled")
                        .disabled(busy)
                }
            }

            SettingsGroup(title: "Instructions") {
                Text(item.data.text("goal")).font(KFont.body()).foregroundStyle(K.text).lineSpacing(4)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(KSpace.lg).frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsGroup(title: "Recent runs") {
                if history.isEmpty {
                    SettingsRow(title: "No runs yet", detail: "Runs started by this schedule appear here.")
                }
                ForEach(Array(history.enumerated()), id: \.element.id) { index, marker in
                    if index > 0 { SettingsDivider() }
                    historyRow(marker)
                }
            }
        }
        .sheet(isPresented: $editing) { AutomationEditorView(item: item) }
        .confirmationDialog("Delete “\(item.data.text("name"))”?", isPresented: $deleting) {
            Button("Delete schedule", role: .destructive) {
                Task {
                    do {
                        try await app.workspace.send("automation.delete", payload: item.idPayload, row: item)
                        app.toasts.show("Schedule deleted")
                    } catch { app.toasts.show("Couldn't delete the schedule. \(error.localizedDescription)", tone: .error) }
                }
            }
        } message: {
            Text("Past runs stay available. This cannot be undone.")
        }
    }

    @ViewBuilder private func historyRow(_ marker: WorkspaceRow) -> some View {
        let started = WorkspaceDate.display(marker.data.text("startedAt"))
        if let run = app.workspace.find("RUN", marker.data.uuid("runId")) {
            ListRow(title: run.data.text("goal"),
                    subtitle: started + (marker.data.flag("coalesced") ? " · missed runs merged" : ""),
                    action: { app.openWorkRun(run.id.uuidString) }) {
                IconTile(icon: "file-text")
            } trailing: {
                StatusBadge(status: run.data.text("status"))
            }
        } else {
            ListRow(title: marker.data.text("error").isEmpty ? "Run no longer available" : marker.data.text("error"),
                    subtitle: started) {
                IconTile(icon: "circle-alert", color: K.warning)
            }
        }
    }

    private func runNow() {
        running = true
        Task {
            defer { running = false }
            do {
                let receipt = try await app.workspace.send(
                    "automation.run_now", payload: item.idPayload, row: item)
                app.openWorkRun(receipt.operationId.uuidString)
            } catch { app.toasts.show("Couldn't start the run. \(error.localizedDescription)", tone: .error) }
        }
    }
}
