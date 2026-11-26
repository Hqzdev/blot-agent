import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceTaughtRecordingEditor: View {
    let skill: BlotV3.Skill
    let recordingID: UUID
    var onSaved: @MainActor () -> Void = {}
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var recording: WorkspaceTaughtTask?
    @State private var name = ""
    @State private var working = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    static func identifier(_ revision: BlotV3.SkillRevision) -> UUID? {
        guard revision.toolIds == ["desktop_replay"], let range = revision.instructions.range(of: #"recording_id ([A-Fa-f0-9-]{36})"#, options: .regularExpression) else { return nil }
        return UUID(uuidString: String(revision.instructions[range]).replacingOccurrences(of: "recording_id ", with: ""))
    }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                if let recording {
                    TextField(store.t("Name"), text: $name)
                    Text(recording.application).font(.headline)
                    Text(ru ? "Изменения сохранятся новой версией навыка. Запуск и запись действий доступны на Mac; iPhone редактирует шаги и отправляет запуск связанному Mac." : "Edits create a new skill revision. Recording and execution run on Mac; iPhone can edit steps and request execution on a paired Mac.").font(.caption).foregroundStyle(.secondary)
                    ForEach(recording.steps.indices, id: \.self) { index in
                        step(recording.steps[index], index: index)
                    }
                } else if failure == nil { ProgressView() }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.disabled(working)

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "Шаги записанной задачи" : "Recorded task steps") {
                    Button(store.t("Close")) { dismiss() }.disabled(working)
                    Button(store.t("Save")) { save() }.buttonStyle(WorkspaceButtonStyle(.primary)).disabled(working || recording?.steps.isEmpty != false || name.isEmpty)
                }
            }.workspaceEditorChrome()
        }
        .task {
            do { recording = try await store.teachCommands?.teaching(recordingID); name = skill.name }
            catch { failure = WorkspaceFailureCopy.message(error) }
        }
        .interactiveDismissDisabled(working)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }
    private func step(_ step: WorkspaceTaughtTask.Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let target = step.target.title.isEmpty ? step.target.identifier : step.target.title
            Text("\(index + 1). \(step.action.rawValue) · \(target)")
            if step.action == .setValue {
                TextField(ru ? "Значение" : "Value", text: Binding(get: { recording?.steps.first { $0.id == step.id }?.value ?? "" }, set: { value in
                    if let position = recording?.steps.firstIndex(where: { $0.id == step.id }) { recording?.steps[position].value = value }
                }), axis: .vertical).lineLimit(2...8)
            }
            HStack {
                Button { move(step.id, by: -1) } label: { BlotIcon(symbol: "arrow.up") }.disabled(index == 0).accessibilityLabel(ru ? "Шаг выше" : "Move step up")
                Button { move(step.id, by: 1) } label: { BlotIcon(symbol: "arrow.down") }.disabled(index + 1 == recording?.steps.count).accessibilityLabel(ru ? "Шаг ниже" : "Move step down")
                Spacer()
                Button(store.t("Delete"), role: .destructive) { recording?.steps.removeAll { $0.id == step.id } }
            }
        }
    }
    private func move(_ id: UUID, by delta: Int) {
        guard let index = recording?.steps.firstIndex(where: { $0.id == id }), let count = recording?.steps.count, (0..<count).contains(index + delta) else { return }
        recording?.steps.swapAt(index, index + delta)
    }
    private func save() {
        guard !working, let recording, let commands = store.teachCommands else { return }; working = true; failure = nil
        _Concurrency.Task {
            defer { working = false }
            do { try await commands.updateTeaching(recording, name: name, skill: skill); try await store.refreshSkills(); onSaved(); dismiss() }
            catch { failure = WorkspaceSkillFailure.text(error, russian: ru) }
        }
    }
}
