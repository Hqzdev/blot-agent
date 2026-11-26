import BlotDesign
import BlotDomain
import BlotWorkspace
import Foundation
import QuickLook
import SwiftUI

struct WorkspaceLocalFileView: View {
    var artifactID: UUID? = nil
    @Environment(WorkspaceStore.self) private var store
    @State private var editor: WorkspaceDocumentEditSession?
    @State private var url: URL?
    @State private var preview: URL?
    @State private var read: WorkspaceExtractedText?
    @State private var table: [[String]]?
    @State private var page = 1
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var file: BlotV3.Artifact? {
        if let artifactID { return store.snapshot.artifacts.first { $0.metadata.id == artifactID } }
        return store.selectedFile
    }
    private struct ReadRequest: Hashable { let id: UUID?; let page: Int; let revision: UUID?; let revisions: [UUID] }

    var body: some View {
        Group {
            #if os(macOS)
            if let editor {
                WorkspaceReportEditor(session: editor, fileName: file?.name ?? editor.draft.title, url: url, fileFailure: failure)
            } else { fallback }
            #else
            fallback
            #endif
        }
        .quickLookPreview($preview)
        .onChange(of: file?.metadata.id) { _, _ in page = 1; preview = nil; editor = nil }
        .task(id: ReadRequest(id: file?.metadata.id, page: page, revision: editor?.saved.revisionID, revisions: file.map { store.chatContent.documentRevisions[$0.metadata.id] ?? [] } ?? [])) {
            read = nil; table = nil; failure = nil; url = nil
            guard let id = file?.metadata.id else { failure = store.t("File is unavailable"); return }
            do {
                guard let files = store.fileCommands else { throw WorkspaceServiceError.unavailable }
                if let cached = store.documentEdits[id] {
                    if !cached.dirty, let current = try? await files.editableWorkspaceDocument(id) { cached.refresh(current) }
                    editor = cached
                }
                else if let document = try await files.editableWorkspaceDocument(id) {
                    try _Concurrency.Task.checkCancellation()
                    let session = WorkspaceDocumentEditSession(document)
                    session.editing = store.documentOpeningModes[id] ?? false
                    store.documentEdits[id] = session; editor = session
                }
                let exportID = editor?.saved.exportArtifactID ?? id
                let localURL = try await store.localFileURL(exportID)
                try _Concurrency.Task.checkCancellation()
                url = localURL
                if editor != nil || file?.mediaType == "application/pdf" { return }
                let result = try await files.readWorkspaceFile(exportID, startPage: page, pageCount: 1)
                try _Concurrency.Task.checkCancellation()
                read = result
                if file?.mediaType == "text/csv", (file?.byteCount ?? Int.max) <= 2 * 1024 * 1024 {
                    let rows = try await _Concurrency.Task.detached(priority: .userInitiated) {
                        try WorkspaceCSV().rows(String(contentsOf: localURL, encoding: .utf8))
                    }.value
                    try _Concurrency.Task.checkCancellation()
                    table = rows
                }
            } catch is CancellationError { return }
            catch { failure = WorkspaceFileFailure.text(error, russian: ru) }
        }
    }
    @ViewBuilder private var fallback: some View {
        #if os(macOS)
        if file?.mediaType == "application/pdf", editor == nil {
            fallbackContent.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { fallbackContent }
        }
        #else
        ScrollView { fallbackContent }
        #endif
    }

    private var fallbackContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if os(macOS)
            HStack(spacing: 8) {
                BlotLabel(store.t("Files"), symbol: "folder").foregroundStyle(.secondary)
                BlotIcon(symbol: "chevron.right", size: 12).foregroundStyle(.tertiary)
                Text(file?.name ?? store.t("Files")).lineLimit(2).textSelection(.enabled)
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            #endif
            if let editor { WorkspaceDocumentEditor(session: editor) }
            if let url, editor?.editing != true {
                HStack {
                    Button(store.t("Open file")) { preview = url }.disabled(editor?.dirty == true)
                    ShareLink(item: url) { Text(store.t("Share")) }.disabled(editor?.dirty == true)
                }
            }
            if let editor, !editor.editing {
                WorkspaceDocumentDraftPreview(document: editor.draft)
            } else if editor == nil {
                if let file, file.mediaType.hasPrefix("image/") {
                    WorkspaceCounter(title: ru ? "Страница" : "Page", value: $page, range: 1...(read?.totalPages ?? 1_000))
                    if let read { Text(ru ? "Всего: \(read.totalPages)" : "Total: \(read.totalPages)").font(.caption).foregroundStyle(.secondary) }
                }
                if let url, file?.mediaType == "application/pdf" {
                    WorkspacePDFPreview(url: url)
                        #if os(iOS)
                        .frame(minHeight: 440, idealHeight: 560)
                        #endif
                } else if let table {
                    WorkspaceTablePreview(rows: table)
                } else if let read {
                    if read.usedOCR { BlotLabel(ru ? "Текст распознан на устройстве" : "Text recognized on this device", symbol: "text.viewfinder").font(.caption).foregroundStyle(.secondary) }
                    WorkspaceMessageBody(text: read.content, markdown: file?.mediaType == "text/markdown", agents: [], skills: [])
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if read.truncated && read.content.count >= 48_000 {
                        Text(ru ? "Показана часть текста. Полное содержимое доступно в оригинале файла." : "Part of the text is shown. Open the original for the full content.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let failure { Text(failure).foregroundStyle(WorkspaceStyle.secondary) }
                else { ProgressView(ru ? "Чтение и распознавание…" : "Reading and recognizing…") }
            }
        }
        #if os(iOS)
        .frame(maxWidth: 640, alignment: .leading).padding(PhonePageLayout.inset).frame(maxWidth: .infinity)
        #else
        .padding(24)
        #endif
    }
}
