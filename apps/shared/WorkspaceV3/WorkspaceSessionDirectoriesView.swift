import BlotWorkspace
import BlotDomain
import SwiftUI

/// Optional owner controls; normal file work needs no visit to this screen.
struct WorkspaceSessionDirectoriesView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var directories: [WorkspaceSessionDirectoryGrant] = []
    @State private var error: String?
    @State private var resolving: UUID?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        if store.sessionFileService?.automaticSessionFiles == true {
            VStack(alignment: .leading, spacing: 12) {
                Text(ru ? "Рабочая папка Blot" : "Blot working folder").font(.headline)
                Text(ru ? "~/Blot создаётся автоматически. У каждого чата — своя папка с историей и рабочими файлами. Доступ к другим папкам агент запрашивает прямо из чата." : "~/Blot is created automatically. Each chat has its own history and working files. Agents request access to other folders directly from the chat.")
                ForEach(directories) { directory in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(directory.path).font(.caption).textSelection(.enabled)
                            Text(store.snapshot.agents.first { $0.metadata.id == directory.agentID }?.name ?? directory.agentID.uuidString).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(ru ? "Отозвать" : "Revoke", role: .destructive) { revoke(directory.id) }
                    }
                }
                ForEach(unknownActions, id: \.metadata.id) { invocation in
                    VStack(alignment: .leading) {
                        Text(ru ? "Проверьте результат файлового действия" : "Verify the file action outcome").font(.headline)
                        Text(ru ? "Ответ был потерян. Действие не повторяется автоматически. Сначала проверьте файл или папку." : "The reply was lost. The action is not replayed. Check the file or folder first.").font(.caption)
                        Button(ru ? "Я проверил результат…" : "I verified the result…") { resolving = invocation.metadata.id }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .task { await refresh() }
            .confirmationDialog(ru ? "Подтвердите проверенный результат" : "Confirm the verified outcome", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
                Button(ru ? "Выполнено" : "Completed") { resolve(true) }
                Button(ru ? "Не выполнено" : "Not completed") { resolve(false) }
            }
        }
    }
    private var unknownActions: [BlotDomain.BlotV3.ToolInvocation] {
        let ids = Set((store.snapshot.preparedActions ?? []).filter { $0.toolId.hasPrefix("workspace_") }.map(\.metadata.id))
        return (store.snapshot.toolInvocations ?? []).filter { $0.state == .unknown && $0.execution.executorDeviceId == store.snapshot.localDeviceID && ids.contains($0.preparedActionId) }
    }
    private func refresh() async {
        do {
            guard let local = store.sessionFileService, let service = try await local.sessionFileService() else { return }
            directories = try await service.directories()
            let mirrorError = await local.sessionMirror?.lastError
            error = local.sessionFilesFailure ?? mirrorError
        } catch { self.error = error.localizedDescription }
    }
    private func revoke(_ id: UUID) {
        _Concurrency.Task {
            do { try await store.sessionFileService?.sessionFileService()?.revokeDirectory(id); await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func resolve(_ succeeded: Bool) {
        guard let id = resolving else { return }; resolving = nil
        _Concurrency.Task {
            do { try await store.sessionFileService?.sessionFileService()?.resolve(invocationID: id, succeeded: succeeded); try await store.refreshMCP() }
            catch { self.error = error.localizedDescription }
        }
    }
}
