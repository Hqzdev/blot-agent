import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspaceDocumentDraftPreview: View {
    struct SavedPDF {
        let url: URL?
        let failure: String?
    }

    let document: WorkspaceEditableDocument
    var savedPDF: SavedPDF? = nil
    @Environment(WorkspaceStore.self) private var store
    @State private var url: URL?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch document.kind {
            case .table: WorkspaceTablePreview(rows: [document.columns] + document.rows)
            case .markdown, .text:
                Text(document.title).font(.title2.weight(.semibold))
                WorkspaceMessageBody(text: document.body, markdown: document.kind == .markdown, agents: [], skills: []).textSelection(.enabled)
            case .pdf, .presentation:
                if let savedPDF {
                    pdf(url: savedPDF.url, failure: savedPDF.failure)
                } else {
                    pdf(url: url, failure: failure)
                        .task(id: document) { await renderDraft() }
                }
            }
        }
    }

    @ViewBuilder private func pdf(url: URL?, failure: String?) -> some View {
        if let url {
            WorkspacePDFPreview(url: url)
                #if os(iOS)
                .frame(minHeight: 440, idealHeight: 560)
                #endif
        } else if let failure {
            Text(failure).foregroundStyle(.secondary)
        } else {
            ProgressView()
        }
    }

    private func renderDraft() async {
        url = nil
        failure = nil
        do {
            guard let commands = store.fileCommands else { throw WorkspaceServiceError.unavailable }
            let local = try await commands.previewWorkspaceDocument(document)
            try _Concurrency.Task.checkCancellation()
            url = local
        } catch {
            guard !_Concurrency.Task.isCancelled else { return }
            failure = store.language == "ru" ? "Для предпросмотра заполните заголовки и текст слайдов. Текст должен помещаться на слайд." : "Fill the slide titles and bodies. Text must fit on each slide."
        }
    }
}
