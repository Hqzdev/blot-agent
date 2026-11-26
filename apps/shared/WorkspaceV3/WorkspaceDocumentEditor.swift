import BlotAppleIntegrations
import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspaceDocumentEditor: View {
    @Bindable var session: WorkspaceDocumentEditSession
    @Environment(WorkspaceStore.self) private var store
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { modes; Spacer(minLength: 8); actions }
                VStack(alignment: .leading, spacing: 10) { modes; HStack { Spacer(); actions } }
            }
            status
            if let failure = session.failure { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if session.conflict {
                Button(ru ? "Загрузить актуальную версию" : "Load latest version") { _Concurrency.Task { await session.reload(using: store) } }.buttonStyle(WorkspaceButtonStyle(.secondary))
            }
            if session.recoveryDraft != nil {
                Button(ru ? "Восстановить мой черновик" : "Restore my draft") { session.recover() }.buttonStyle(WorkspaceButtonStyle(.secondary))
            }
            if session.editing {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ru ? "Заголовок" : "Title").font(.caption).foregroundStyle(.secondary)
                    field(ru ? "Заголовок документа" : "Document title", text: $session.draft.title)
                }
                switch session.draft.kind {
                case .table: WorkspaceTableEditor(session: session)
                case .presentation: WorkspaceSlidesEditor(session: session)
                default:
                    TextEditor(text: $session.draft.body).font(.body).scrollContentBackground(.hidden)
                        .frame(minHeight: 380).padding(14)
                        .background(WorkspaceStyle.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceStyle.ink.opacity(0.1)))
                        .accessibilityLabel(ru ? "Текст документа" : "Document text")
                }
            }
        }
        .disabled(session.saving)
        .kAnimation(KMotion.standard, value: session.editing)
        .onChange(of: session.dirty, initial: true) { _, dirty in
            #if os(macOS)
            if let browser = store.browser, let tab = browser.sessionTabs.first(where: { store.panelNavigations.navigation(for: $0).fileID == session.draft.id }) {
                browser.setLocalDocumentUnsaved(tab.id, dirty)
            }
            #endif
        }
    }
    private var modes: some View {
        HStack(spacing: 4) {
            Button(ru ? "Редактор" : "Edit") { session.editing = true }
                .buttonStyle(WorkspaceButtonStyle(session.editing ? .primary : .secondary))
            Button(ru ? "Предпросмотр" : "Preview") { session.editing = false }
                .buttonStyle(WorkspaceButtonStyle(session.editing ? .secondary : .primary))
        }
    }
    private var actions: some View {
        HStack(spacing: 8) {
            Button(ru ? "Отменить правки" : "Revert") { session.revert() }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(!session.dirty)
            Button { _Concurrency.Task { await session.save(using: store) } } label: {
                BlotLabel(session.saving ? (ru ? "Сохраняю…" : "Saving…") : (ru ? "Сохранить" : "Save"), symbol: "checkmark")
            }.buttonStyle(WorkspaceButtonStyle()).disabled(!session.dirty).keyboardShortcut("s", modifiers: .command)
        }
    }
    private var status: some View {
        Text(session.dirty ? (ru ? "Есть изменения" : "Unsaved changes") : (ru ? "Сохранено" : "Saved"))
            .font(.caption).foregroundStyle(.secondary).fixedSize()
    }
    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).padding(12)
            .background(WorkspaceStyle.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}
