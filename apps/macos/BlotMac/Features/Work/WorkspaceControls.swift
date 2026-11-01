import BlotAPI
import BlotDesign
import SwiftUI

extension BackendEntity where Value == BackendJSON {
    var idPayload: BackendJSON { .object(["id": .string(id.uuidString)]) }
}

/// Sends one workspace command for a record. Shows a spinner while the command is in flight and a
/// toast when it finishes; failures also stay in the workspace banner with a retry.
struct WorkspaceActionButton: View {
    @Environment(AppState.self) private var app
    let title: String
    let command: String
    let row: WorkspaceRow
    var payload: BackendJSON?
    var icon: String?
    var kind: KButtonKind = .standard
    var success: String?

    private var key: String { command + ":" + row.id.uuidString }

    var body: some View {
        KButton(title: title, icon: icon, kind: kind, loading: app.workspace.commands.active.contains(key)) {
            Task {
                do {
                    try await app.workspace.send(command, payload: payload ?? row.idPayload, row: row)
                    if let success { app.toasts.show(success) }
                } catch {
                    app.toasts.show(error.localizedDescription, tone: .error)
                }
            }
        }
    }
}

/// Connection and command state under the toolbar: lost connection, recovery of commands sent
/// before a restart, commands waiting for confirmation. Hidden when everything is in sync.
struct WorkspaceStatusView: View {
    @Environment(AppState.self) private var app
    @State private var refreshing = false
    @State private var showingDetails = false

    var body: some View {
        let workspace = app.workspace
        let error = workspace.recoveryError ?? workspace.error ?? workspace.commands.error
        let pending = Array(workspace.commands.pending.values).sorted { $0.id.uuidString < $1.id.uuidString }
        if error != nil || !pending.isEmpty {
            HStack {
                Spacer()
                Button { showingDetails.toggle() } label: {
                    Label(error == nil ? "Ожидает подтверждения" : "Проверьте подключение",
                          systemImage: error == nil ? "clock" : "exclamationmark.triangle")
                }
                .buttonStyle(KButtonStyle(kind: .standard))
                .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: KSpace.md) {
                        if let error { InlineFeedback(text: error, tone: .error).textSelection(.enabled) }
                        if workspace.recoveryError != nil {
                            KButton(title: "Восстановить отправленные команды", icon: "rotate-ccw",
                                    loading: workspace.recoveringCommands) {
                                Task { await app.recoverWorkspaceCommands() }
                            }
                        }
                        KButton(title: "Подключиться снова", icon: "rotate-ccw", loading: refreshing) {
                            refreshing = true
                            Task { await workspace.refresh(); refreshing = false }
                        }
                        ForEach(pending) { command in
                            Text("Ожидаем подтверждения: \(Self.describe(command.type))").font(KFont.caption())
                            KButton(title: "Отправить повторно", loading: workspace.commands.active.contains(command.key)) {
                                Task {
                                    let receipt = await workspace.commands.retry(command)
                                    await workspace.refresh()
                                    if let receipt { openResult(receipt, command: command) }
                                }
                            }
                        }
                    }.padding(20).frame(width: 380)
                }
            }.padding(.horizontal, KSpace.lg).padding(.top, KSpace.sm)
        }
    }

    /// «run.plan.approve» → «Run plan approve».
    static func describe(_ type: String) -> String {
        let words = type.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private func openResult(_ receipt: BackendReceipt, command: WorkspaceCommands.Pending) {
        if command.type == "run.create" {
            if command.key == "create-team-run" {
                app.openWorkRun(receipt.operationId.uuidString)
            } else if let project = command.projectID {
                app.openTask(projectID: project.uuidString, taskID: receipt.operationId.uuidString)
            }
        } else if command.type == "automation.run_now" {
            app.openWorkRun(receipt.operationId.uuidString)
        } else if command.type == "skill.save" {
            app.skills.selectedID = receipt.operationId
        } else if command.type == "automation.save" {
            app.automations.selectedID = receipt.operationId
        }
    }
}
