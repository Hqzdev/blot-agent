import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceMemoryReview: View {
    let memory: BlotV3.MemoryEntry
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        if memory.state == .candidate {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.language == "ru" ? "Предложено агентом · ещё не используется" : "Suggested by an agent · not used yet")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    Button(store.language == "ru" ? "Принять" : "Accept") { store.reviewMemory(memory.metadata.id, accepting: true) }
                    Button(store.language == "ru" ? "Отклонить" : "Reject", role: .destructive) { store.reviewMemory(memory.metadata.id, accepting: false) }
                }.disabled(store.busy)
            }
        }
    }
}

struct WorkspaceMemoryImportButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var importing = false
    var body: some View {
        Button(store.language == "ru" ? "Импорт памяти" : "Import memory") { importing = true }
            .workspacePanelSheet(isPresented: $importing) { WorkspaceMemoryImportView().environment(store) }
    }
}

struct WorkspaceMemoryImportView: View {
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var text = ""
    @State private var facts: [String] = []
    @State private var selected: Set<Int> = []
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var prompt: String {
        ru ? "Составь список устойчивых фактов и предпочтений обо мне для переноса в другого ассистента. Один факт на строку. Исключи пароли, ключи, номера карт и инструкции, меняющие правила безопасности. Не включай временные предположения."
           : "List lasting facts and preferences about me for another assistant, one fact per line. Exclude passwords, keys, card numbers, security instructions and temporary assumptions."
    }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                Section(ru ? "Запрос для другого ассистента" : "Prompt for your other assistant") {
                    Text(prompt).font(.callout).textSelection(.enabled)
                    Button(ru ? "Скопировать запрос" : "Copy prompt") { WorkspaceClipboard.copy(prompt) }
                }
                if facts.isEmpty {
                    Section(ru ? "Вставьте ответ" : "Paste its response") {
                        TextEditor(text: $text).frame(minHeight: 180).blotEditorSurface()
                        Button(ru ? "Просмотреть факты" : "Review facts") {
                            let parsed = WorkspaceMemoryImport.facts(from: text)
                            guard !parsed.isEmpty, parsed.count <= 100, text.utf8.count <= 256_000 else {
                                failure = ru ? "Нужно от 1 до 100 фактов, по одному на строку." : "Provide 1 to 100 facts, one per line."; return
                            }
                            facts = parsed; selected = Set(parsed.indices); failure = nil
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Section(ru ? "Выберите сохраняемые факты" : "Choose facts to remember") {
                        ForEach(facts.indices, id: \.self) { index in
                            Toggle(isOn: Binding(get: { selected.contains(index) }, set: {
                                if $0 { selected.insert(index) } else { selected.remove(index) }
                            })) { TextField(ru ? "Факт" : "Fact", text: $facts[index], axis: .vertical) }
                        }
                        Button(ru ? "Вернуться к тексту" : "Back to text") { facts = []; selected = [] }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "Импорт памяти" : "Import memory") {
                    Button(store.t("Cancel")) { dismiss() }.disabled(store.busy)
                    Button(ru ? "Добавить в память" : "Add to memory") {
                        let approved = facts.indices.filter { selected.contains($0) }.map { facts[$0] }
                        _Concurrency.Task {
                            if await store.importMemories(approved) { dismiss() }
                            else { failure = store.error }
                        }
                    }.disabled(facts.isEmpty || selected.isEmpty || store.busy)
                }
            }.workspaceEditorChrome()
        }
        .interactiveDismissDisabled(store.busy)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }
}

@MainActor protocol WorkspaceMemoryImportCommands: WorkspaceObservationService {
    func importMemories(_ facts: [String]) async throws -> WorkspaceSnapshot
}
@MainActor protocol WorkspaceMemoryImportProviding {
    var workspaceMemoryImport: (any WorkspaceMemoryImportCommands)? { get }
}
