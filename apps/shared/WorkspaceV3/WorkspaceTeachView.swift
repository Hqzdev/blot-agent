import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspaceTeachProviding {
    func teachRequest(_ operation: NativeRequest.Operation, parameters: [String: String]) async throws -> ChatJSON
    func saveTeaching(_ recording: WorkspaceTaughtTask, name: String) async throws -> UUID
    func teaching(_ id: UUID) async throws -> WorkspaceTaughtTask
    func updateTeaching(_ recording: WorkspaceTaughtTask, name: String, skill: BlotV3.Skill) async throws
}
extension LocalWorkspaceService: WorkspaceTeachProviding {
    func teachingExecutor() -> any NativeExecuting {
        if let teachExecutor { return teachExecutor }
        let value = makeNativeExecutor(); teachExecutor = value; return value
    }
    func teachRequest(_ operation: NativeRequest.Operation, parameters: [String: String] = [:]) async throws -> ChatJSON {
        try await teachingExecutor().request(WorkspaceTeachTools.request(operation, identity: context(), parameters: parameters))
    }
    func saveTeaching(_ recording: WorkspaceTaughtTask, name: String) async throws -> UUID {
        try await persistTeaching(recording, name: name, skill: nil)
    }
    func teaching(_ id: UUID) async throws -> WorkspaceTaughtTask {
        let data = try await fileService().data(for: id)
        guard data.count <= 120_000 else { throw WorkspaceStorageError.invalidParameters }
        let recording = try JSONDecoder().decode(WorkspaceTaughtTask.self, from: data); try recording.validate(); return recording
    }
    func updateTeaching(_ recording: WorkspaceTaughtTask, name: String, skill: BlotV3.Skill) async throws {
        _ = try await persistTeaching(recording, name: name, skill: skill)
    }
    private func persistTeaching(_ recording: WorkspaceTaughtTask, name: String, skill: BlotV3.Skill?) async throws -> UUID {
        try recording.validate()
        let id = try await fileService().store(commandID: UUID(), name: "Teach " + recording.application.replacingOccurrences(of: "/", with: "-") + ".json", mediaType: "application/json", data: JSONEncoder().encode(recording))
        return try await saveSkill(id: skill?.metadata.id, version: skill?.metadata.version ?? 0, name: name,
            instructions: "Run the user-reviewed recording in " + recording.application + " using desktop_replay with recording_id " + id.uuidString + ". Inspect the result. If execution stops, report the completed step count; do not retry automatically.", parameters: [], tools: ["desktop_replay"])
    }
    func teachTools() async throws -> WorkspaceTeachTools {
        let center = appleIntegrations.interactions
        return WorkspaceTeachTools(repository: repository, identity: try await context(), files: try await fileService(), executor: teachingExecutor()) { title, details in
            try await center.confirm(title: title, details: details)
        }
    }
}
extension WorkspaceAccountApplicationService: WorkspaceTeachProviding {
    func teaching(_ id: UUID) async throws -> WorkspaceTaughtTask {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }; return try await local.teaching(id)
    }
    func updateTeaching(_ recording: WorkspaceTaughtTask, name: String, skill: BlotV3.Skill) async throws {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }; try await local.updateTeaching(recording, name: name, skill: skill)
    }
    func teachRequest(_ operation: NativeRequest.Operation, parameters: [String: String]) async throws -> ChatJSON {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        return try await local.teachRequest(operation, parameters: parameters)
    }
    func saveTeaching(_ recording: WorkspaceTaughtTask, name: String) async throws -> UUID {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        return try await local.saveTeaching(recording, name: name)
    }
}

struct WorkspaceTeachButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        #if os(macOS)
        Button { showing = true } label: { BlotLabel(store.language == "ru" ? "Обучить задаче" : "Teach a task", symbol: "record.circle") }
            .workspacePanelSheet(isPresented: $showing) { WorkspaceTeachView().environment(store) }
        #else
        EmptyView()
        #endif
    }
}

private struct WorkspaceTeachView: View {
    private struct Application: Decodable, Identifiable { let bundle_id: String; let name: String; var id: String { bundle_id } }
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var applications: [Application] = []
    @State private var application = ""
    @State private var recording = false
    @State private var paused = false
    @State private var elapsed = 0.0
    @State private var count = 0
    @State private var result: WorkspaceTaughtTask?
    @State private var name = ""
    @State private var working = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                if let result { recordingResult(result) } else { recordingControls }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.disabled(working)

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "Обучить задаче" : "Teach a task") {
                    Button(store.t("Close")) { dismiss() }.disabled(working || recording)
                }
            }.workspaceEditorChrome()
        }
        .task {
            await perform { commands in
                let data = try await commands.teachRequest(.teachApplications, parameters: [:])
                applications = try JSONDecoder().decode([Application].self, from: JSONEncoder().encode(data)).sorted { $0.name < $1.name }
                application = applications.first?.id ?? ""
            }
        }
        .task(id: recording) {
            guard recording else { return }
            while !_Concurrency.Task.isCancelled, recording {
                do {
                    try await _Concurrency.Task.sleep(for: .seconds(1))
                    guard let commands = store.teachCommands else { return }
                    let response = try await commands.teachRequest(.teachStatus, parameters: [:])
                    guard case .object(let state) = response else { throw WorkspaceServiceError.unavailable }
                    if case .number(let seconds) = state["elapsed"] { elapsed = seconds }
                    if case .number(let steps) = state["step_count"] { count = Int(steps) }
                } catch is CancellationError { return }
                catch { failure = WorkspaceFailureCopy.message(error); return }
            }
        }
        .interactiveDismissDisabled(recording || working)
        #if os(macOS)
        .frame(minWidth: 570, minHeight: 540)
        #endif
    }
    private func recordingResult(_ result: WorkspaceTaughtTask) -> some View {
                    Section(ru ? "Результат обучения" : "Recording result") {
                        TextField(store.t("Name"), text: $name)
                        Text(result.application + " · " + String(Int(result.duration)) + (ru ? " сек." : " sec"))
                        Text(ru ? "Проверьте текст каждого шага. Удалите личные данные перед сохранением." : "Review every step and remove private data before saving.").font(.caption).foregroundStyle(.secondary)
                        ForEach(result.steps.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(stepTitle(result.steps[index], index: index))
                                if result.steps[index].action == .setValue {
                                    TextField(ru ? "Значение" : "Value", text: Binding(get: { self.result?.steps[index].value ?? "" }, set: { self.result?.steps[index].value = $0 }), axis: .vertical)
                                }
                                Button(store.t("Delete"), role: .destructive) { self.result?.steps.remove(at: index) }
                            }
                        }
                        Button(ru ? "Сохранить навык" : "Save skill") { save() }.disabled(result.steps.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                    }
    }
    @ViewBuilder private var recordingControls: some View {
                    Section(ru ? "Приложение" : "Application") {
                        WorkspaceChoice(title: ru ? "Записывать только" : "Record only", selection: $application, options: applications.map { .init($0.id, $0.name) }).disabled(recording)
                        Text(ru ? "Записываются доступные кнопки и изменения обычных текстовых полей выбранного приложения. Пароли и сочетания клавиш не записываются. Для исполнителя Ori нужен доступ «Универсальный доступ» в настройках macOS." : "Records accessible buttons and ordinary text-field changes in the selected app. Passwords and keyboard shortcuts are excluded. Grant Accessibility access to the Ori executor in macOS Settings.").font(.caption).foregroundStyle(.secondary)
                    }
                    if recording {
                        BlotLabel(String(Int(elapsed)) + (ru ? " сек. · шагов: " : " sec · steps: ") + String(count), symbol: paused ? "pause.circle" : "record.circle").monospacedDigit().foregroundStyle(.red)
                        Button(paused ? (ru ? "Продолжить" : "Resume") : (ru ? "Пауза" : "Pause")) { pause() }
                        Button(ru ? "Завершить запись" : "Stop recording") { stop() }
                    } else { Button(ru ? "Начать запись" : "Start recording") { start() }.disabled(application.isEmpty) }
    }
    private func stepTitle(_ step: WorkspaceTaughtTask.Step, index: Int) -> String {
        let target = step.target.title.isEmpty ? step.target.identifier : step.target.title
        return "\(index + 1). \(step.action.rawValue) · \(target)"
    }
    private func start() { _Concurrency.Task { await perform { commands in _ = try await commands.teachRequest(.teachStart, parameters: ["bundle_id": application]); recording = true; paused = false } } }
    private func pause() { _Concurrency.Task { await perform { commands in _ = try await commands.teachRequest(.teachPause, parameters: ["paused": String(!paused)]); paused.toggle() } } }
    private func stop() { _Concurrency.Task { await perform { commands in
        let data = try await commands.teachRequest(.teachStop, parameters: [:]); recording = false
        result = try JSONDecoder().decode(WorkspaceTaughtTask.self, from: JSONEncoder().encode(data)); name = result?.application ?? ""
    } } }
    private func save() { guard let result else { return }; _Concurrency.Task { await perform { commands in
        _ = try await commands.saveTeaching(result, name: name); try await store.refreshSkills(); dismiss()
    } } }
    private func perform(_ work: @MainActor (any WorkspaceTeachProviding) async throws -> Void) async {
        guard !working, let commands = store.teachCommands else { return }; working = true; failure = nil
        defer { working = false }
        do { try await work(commands) } catch { failure = WorkspaceFailureCopy.message(error) }
    }
}
