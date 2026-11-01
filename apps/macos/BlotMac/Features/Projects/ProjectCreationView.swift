import BlotAPI
import Observation
import BlotDesign
import SwiftUI

@Observable
final class ProjectCreator {
    var name = ""
    private(set) var busy = false
    private(set) var error: String?
    private(set) var submittedName: String?
    private var commandID = UUID()

    func create(in app: AppState) async -> Bool {
        let title = submittedName ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !title.isEmpty else { return false }
        busy = true
        submittedName = title
        error = nil
        defer { busy = false }
        do {
            let client = BackendRuntime.shared.client
            let receipt = try await client.command("project.create", payload: ["name": title], commandId: commandID)
            let project = try receipt.result.decode(WorkspaceRow.self)
            app.workChat.registerProject(id: project.id.uuidString, name: title)
            await app.workspace.refresh()
            app.openWorkChatProject(project.id.uuidString)
            return true
        } catch {
            self.error = error.localizedDescription
            if let failure = error as? BackendFailure, failure.isDefiniteRejection {
                submittedName = nil
                commandID = UUID()
            }
            return false
        }
    }
}

struct ProjectCreationView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var creator = ProjectCreator()
    @FocusState private var focused: Bool

    var body: some View {
        KSheet("Новый проект", subtitle: "Соберите чаты, заметки и материалы для одной задачи.") {
            VStack(alignment: .leading, spacing: KSpace.sm) {
                Text("Название").font(KFont.label())
                TextField("Например, запуск приложения", text: $creator.name)
                    .textFieldStyle(.roundedBorder).controlSize(.large).focused($focused)
                    .disabled(creator.busy || creator.submittedName != nil)
                    .onSubmit { create() }
                Text("После создания добавьте материалы и начните разговор. Git-репозиторий не требуется.")
                    .font(KFont.caption()).foregroundStyle(K.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = creator.error { InlineFeedback(text: error, tone: .error) }
        } footer: {
            KButton(title: "Отмена", kind: .ghost) { dismiss() }.disabled(creator.busy)
            KButton(title: creator.submittedName == nil ? "Создать проект" : "Повторить", kind: .primary,
                    loading: creator.busy) { create() }
                .disabled(creator.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { focused = true }
        .interactiveDismissDisabled(creator.busy)
    }

    private func create() {
        Task { if await creator.create(in: app) { dismiss() } }
    }
}
