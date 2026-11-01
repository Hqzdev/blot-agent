import BlotAPI
import Observation
import PDFKit
import BlotDesign
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ProjectMaterialDraft {
    var title = ""
    var content = ""
    private(set) var busy = false
    private(set) var error: String?
    private var commandID = UUID()
    private(set) var submitted = false
    private var request: BackendJSON?
    var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title.count + content.count + 2 <= 16000
    }

    func importFile(_ url: URL) {
        do {
            let data = try LocalPreviewReader.read(url, maxBytes: 1_000_000)
            let text = url.pathExtension.lowercased() == "pdf"
                ? PDFDocument(data: data)?.string : String(data: data, encoding: .utf8)
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalPreviewError.unsupported
            }
            title = url.lastPathComponent
            content = text
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func save(projectID: UUID, in app: AppState) async -> Bool {
        guard !busy, valid else { return false }
        if request == nil {
            request = .object(["data": .object([
                "scope": .string("project"), "status": .string("active"),
                "content": .string(title.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + content)
            ])])
        }
        guard let request else { return false }
        busy = true
        submitted = true
        error = nil
        defer { busy = false }
        do {
            _ = try await BackendRuntime.shared.client.command("memory.save", payload: request,
                                                               projectId: projectID, commandId: commandID)
            await app.workspace.refresh()
            return true
        } catch {
            self.error = error.localizedDescription
            if let failure = error as? BackendFailure, failure.isDefiniteRejection {
                self.request = nil
                submitted = false
                commandID = UUID()
            }
            return false
        }
    }
}

struct ProjectMaterialEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var draft = ProjectMaterialDraft()
    @State private var importing = false

    var body: some View {
        KSheet("Добавить материал", subtitle: "Blot сможет использовать его в чатах этого проекта.", width: 580) {
            TextField("Название материала", text: $draft.title).textFieldStyle(.roundedBorder)
                .disabled(draft.submitted)
            TextEditor(text: $draft.content).font(KFont.body()).frame(height: 190)
                .padding(8).background(K.surface2, in: RoundedRectangle(cornerRadius: K.rMd))
                .disabled(draft.submitted)
                .accessibilityLabel("Текст материала")
            HStack {
                KButton(title: "Выбрать файл…", icon: "doc.text") { importing = true }
                    .disabled(draft.submitted)
                Spacer()
                Text("\(draft.title.count + draft.content.count + 2) / 16 000")
                    .font(KFont.caption()).foregroundStyle(draft.content.count + draft.title.count + 2 > 16000 ? K.danger : K.text2)
            }
            Text("Текст, Markdown, JSON или PDF с текстовым слоем, до 1 МБ. Можно написать заметку прямо здесь.")
                .font(KFont.caption()).foregroundStyle(K.text2)
            if let error = draft.error { InlineFeedback(text: error, tone: .error) }
        } footer: {
            KButton(title: "Отмена", kind: .ghost) { dismiss() }.disabled(draft.busy)
            KButton(title: draft.submitted ? "Повторить" : "Добавить", kind: .primary, loading: draft.busy) {
                Task { if await draft.save(projectID: projectID, in: app) { dismiss() } }
            }.disabled(!draft.valid).keyboardShortcut(.defaultAction)
        }
        .interactiveDismissDisabled(draft.busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .sourceCode, .json, .pdf, .text]) { result in
            switch result {
            case .success(let url): draft.importFile(url)
            case .failure(let error): app.toasts.show(error.localizedDescription, tone: .error)
            }
        }
    }
}
