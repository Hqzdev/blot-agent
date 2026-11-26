import BlotAppleIntegrations
#if os(macOS)
import AppKit
import BlotDesign
import BlotWorkspace
import SwiftUI

/// A document tab owns its draft; switching preview/source never discards edits.
struct WorkspaceReportEditor: View {
    @Bindable var session: WorkspaceDocumentEditSession
    let fileName: String
    let url: URL?
    let fileFailure: String?
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    private var ru: Bool { store.language == "ru" }
    private var structured: Bool { session.draft.kind == .table || session.draft.kind == .presentation }
    private var source: String { WorkspaceReportSource.text(session.draft) }
    private var showsTitle: Bool {
        guard session.draft.sourceFileExtension == nil, !structured else { return false }
        let first = session.draft.body.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
        return first != "# " + session.draft.title
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(WorkspaceStyle.ink.opacity(0.04))
            if session.failure != nil || session.conflict || session.recoveryDraft != nil { recovery }
            if session.editing { editor }
            else if session.draft.kind == .presentation {
                WorkspaceDocumentDraftPreview(document: session.draft,
                    savedPDF: session.dirty ? nil : .init(url: url, failure: fileFailure))
                    .frame(maxWidth: 1000, maxHeight: .infinity, alignment: .topLeading)
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if showsTitle {
                            Text(session.draft.title).font(.system(size: 30, weight: .semibold)).textSelection(.enabled)
                        }
                        if session.draft.kind == .table {
                            WorkspaceDocumentDraftPreview(document: session.draft)
                        } else {
                            WorkspaceMessageBody(text: session.draft.body,
                                markdown: session.draft.kind == .markdown || session.draft.kind == .pdf, agents: [], skills: [], report: true)
                                .font(.system(size: 16)).lineSpacing(7).textSelection(.enabled)
                        }
                    }.frame(maxWidth: 1000, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(WorkspaceStyle.canvas)
        .onChange(of: session.dirty, initial: true) { _, dirty in
            if let browser = store.browser, let tab = browser.sessionTabs.first(where: { store.panelNavigations.navigation(for: $0).fileID == session.draft.id }) {
                browser.setLocalDocumentUnsaved(tab.id, dirty)
            }
        }
        .accessibilityIdentifier("workspace.file.report-editor")
    }

    private var toolbar: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        BlotIcon(symbol: "folder", size: 15).foregroundStyle(.secondary)
                        Button(store.t("Files")) {
                            if let panelNavigation { panelNavigation.open(.files) }
                            else { store.navigate(.files) }
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                        BlotIcon(symbol: "chevron.right", size: 10).foregroundStyle(.tertiary)
                        Text(fileName).fontWeight(.medium).lineLimit(1)
                        if session.dirty { Circle().fill(WorkspaceStyle.ink.opacity(0.45)).frame(width: 5, height: 5).accessibilityLabel(ru ? "Есть изменения" : "Unsaved changes") }
                    }.font(.system(size: 13)).padding(.horizontal, 13).frame(height: 36)
                        .background(WorkspaceStyle.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(WorkspaceStyle.ink.opacity(0.07)))
                    Spacer(minLength: 12)
                    Button { store.showChanges(.init(kind: .draft, id: session.draft.id)) } label: {
                        BlotLabel(ru ? "Изменения" : "Show changes", symbol: "square.and.pencil")
                    }.buttonStyle(WorkspaceButtonStyle(.secondary))
                        .accessibilityIdentifier("workspace.file.show-changes")
                    Button { withAnimation(.easeInOut(duration: 0.18)) { session.editing.toggle() } } label: {
                        BlotLabel(session.editing ? (ru ? "Документ" : "View document") : (structured ? (ru ? "Редактировать" : "Edit") : (ru ? "Исходник" : "View source")),
                            symbol: session.editing ? "doc.text" : "doc.text.magnifyingglass")
                    }.buttonStyle(WorkspaceButtonStyle(.secondary)).accessibilityIdentifier("workspace.file.source-mode")
                    if session.editing || session.dirty {
                        Button { _Concurrency.Task { await session.save(using: store) } } label: {
                            BlotLabel(session.saving ? (ru ? "Сохраняю…" : "Saving…") : (ru ? "Сохранить" : "Save"), symbol: "checkmark")
                        }.buttonStyle(WorkspaceButtonStyle()).disabled(!session.dirty || session.saving)
                            .keyboardShortcut("s", modifiers: .command).accessibilityIdentifier("workspace.file.save")
                    }
                    WorkspaceFileActionsMenu {
                        if let url {
                            Button(ru ? "Открыть в приложении по умолчанию" : "Open in default app") { NSWorkspace.shared.open(url) }
                                .disabled(session.dirty)
                            ShareLink(item: url) { BlotLabel(ru ? "Поделиться файлом" : "Share file", symbol: "square.and.arrow.up") }.buttonStyle(MacMenuRowStyle()).disabled(session.dirty)
                        }
                        Button(ru ? "Отменить несохранённые правки" : "Revert unsaved changes") { session.revert() }
                            .disabled(!session.dirty || session.saving)
                    } label: { BlotLabel(ru ? "Открыть" : "Open", symbol: "arrow.up.right.square") }
                        .fixedSize().padding(.horizontal, 12).frame(height: 36)
                        .background(WorkspaceStyle.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(WorkspaceStyle.ink.opacity(0.07)))
                    Button { WorkspaceClipboard.copy(source) } label: { BlotIcon(symbol: "doc.on.doc", size: 17).frame(width: 36, height: 36) }
                        .buttonStyle(BlotPlainButtonStyle(hoverIn: Circle())).background(WorkspaceStyle.surface, in: Circle())
                        .accessibilityLabel(ru ? "Скопировать содержимое" : "Copy contents")
                }.padding(.horizontal, 16).padding(.vertical, 10).frame(minWidth: geometry.size.width)
            }.scrollIndicators(.hidden)
        }.frame(height: 58)
    }

    @ViewBuilder private var editor: some View {
        if session.draft.kind == .table || session.draft.kind == .presentation {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleField
                    if session.draft.kind == .table { WorkspaceTableEditor(session: session) }
                    else { WorkspaceSlidesEditor(session: session) }
                }.padding(26)
            }.disabled(session.saving)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if session.draft.sourceFileExtension == nil { titleField.padding(.horizontal, 26).padding(.top, 20) }
                TextEditor(text: $session.draft.body).font(.system(size: 14, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(.horizontal, 22).padding(.vertical, 16)
                    .accessibilityLabel(ru ? "Исходный текст файла" : "File source text")
                    .accessibilityIdentifier("workspace.file.source-editor")
            }.disabled(session.saving)
        }
    }
    private var titleField: some View {
        TextField(ru ? "Название документа" : "Document title", text: $session.draft.title)
            .textFieldStyle(.plain).font(.system(size: 25, weight: .semibold))
    }
    private var recovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let failure = session.failure { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if session.conflict {
                    Button(ru ? "Загрузить актуальную версию" : "Load latest version") { _Concurrency.Task { await session.reload(using: store) } }
                }
                if session.recoveryDraft != nil { Button(ru ? "Восстановить мой черновик" : "Restore my draft") { session.recover() } }
            }.buttonStyle(WorkspaceButtonStyle(.secondary))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
}

nonisolated enum WorkspaceReportSource {
    static func text(_ document: WorkspaceEditableDocument) -> String {
        (try? comparisonText(document)) ?? ""
    }

    static func comparisonText(_ document: WorkspaceEditableDocument) throws -> String {
        switch document.kind {
        case .table:
            return String(decoding: try WorkspaceDocumentWriter().csv(headers: document.columns, rows: document.rows), as: UTF8.self)
        case .presentation: return document.slides.map { "# " + $0.title + "\n\n" + $0.body }.joined(separator: "\n\n---\n\n")
        case .markdown:
            return document.sourceFileExtension == nil ? "# " + document.title + "\n\n" + document.body + "\n" : document.body
        case .pdf: return "# " + document.title + "\n\n" + document.body
        default: return document.body
        }
    }
}
#endif
