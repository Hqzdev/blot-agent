import BlotWorkspace
import Foundation
import Observation

/// Window-session drafts survive tab navigation. A failed save never replaces the user's draft.
@MainActor @Observable
final class WorkspaceDocumentEditSession {
    var saved: WorkspaceEditableDocument
    var draft: WorkspaceEditableDocument
    var editing = true
    var saving = false
    var failure: String?
    var conflict = false
    var recoveryDraft: WorkspaceEditableDocument?
    var slide = 0
    var tablePage = 0
    var dirty: Bool { draft != saved }
    init(_ document: WorkspaceEditableDocument) { saved = document; draft = document }
    func revert() { draft = saved; failure = nil; conflict = false }
    func refresh(_ document: WorkspaceEditableDocument) {
        guard !dirty else { return }; saved = document; draft = document
    }
    func reload(using store: WorkspaceStore) async {
        guard !saving, let files = store.fileCommands else { return }
        do {
            guard let current = try await files.editableWorkspaceDocument(draft.id) else { return }
            recoveryDraft = draft; saved = current; draft = current; conflict = false; failure = nil
        } catch { failure = store.language == "ru" ? "Актуальная версия пока недоступна. Черновик сохранён в редакторе." : "The latest version is unavailable. Your draft is retained." }
    }
    func recover() {
        guard let recoveryDraft else { return }
        draft.title = recoveryDraft.title; draft.body = recoveryDraft.body; draft.columns = recoveryDraft.columns
        draft.rows = recoveryDraft.rows; draft.slides = recoveryDraft.slides
        self.recoveryDraft = nil
    }
    func save(using store: WorkspaceStore) async {
        guard !saving, dirty, let files = store.fileCommands else { return }
        saving = true; failure = nil
        defer { saving = false }
        do {
            let document = try await files.saveWorkspaceDocument(draft, commandID: UUID())
            saved = document; draft = document
            try await store.refreshContent()
            conflict = false; recoveryDraft = nil
        } catch {
            if error as? WorkspaceStorageError == .versionConflict {
                conflict = true
                failure = store.language == "ru" ? "Документ изменён в другом окне или на другом устройстве. Ваш текст сохранён в черновике; откройте актуальную версию перед повторной записью." : "The document changed elsewhere. Your draft is retained; reopen the latest version before saving again."
            } else {
                failure = store.language == "ru" ? "Не удалось сохранить. Проверьте заголовок, размер таблицы и заполнение слайдов. Черновик остаётся в редакторе." : "Could not save. Check the title, table size and slide content. Your draft remains in the editor."
            }
        }
    }
}
