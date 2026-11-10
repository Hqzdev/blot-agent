import BlotDesign
import BlotDomain
import BlotWorkspace
import Foundation
import QuickLook
import SwiftUI

struct WorkspaceLocalFileView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var url: URL?
    @State private var preview: URL?
    @State private var read: WorkspaceExtractedText?
    @State private var page = 1
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private struct ReadRequest: Hashable { let id: UUID?; let page: Int }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(macOS)
                Text(store.selectedFile?.name ?? store.t("Files")).font(.title2).textSelection(.enabled)
                #endif
                if let url {
                    HStack {
                        Button(store.t("Open file")) { preview = url }
                        ShareLink(item: url) { Text(store.t("Share")) }
                    }
                }
                if let file = store.selectedFile, file.mediaType == "application/pdf" || file.mediaType.hasPrefix("image/") {
                    Stepper(value: $page, in: 1...(read?.totalPages ?? 1_000)) {
                        Text(ru ? "Страница \(page)" : "Page \(page)")
                        if let read { Text(ru ? "Всего: \(read.totalPages)" : "Total: \(read.totalPages)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let read {
                    if read.usedOCR { Label(ru ? "Текст распознан на устройстве" : "Text recognized on this device", systemImage: "text.viewfinder").font(.caption).foregroundStyle(.secondary) }
                    Text(read.content).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if read.truncated && read.content.count >= 48_000 {
                        Text(ru ? "Показана часть текста. Полное содержимое доступно в оригинале файла." : "Part of the text is shown. Open the original for the full content.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let failure { Text(failure).foregroundStyle(WorkspaceStyle.secondary) }
                else { ProgressView(ru ? "Чтение и распознавание…" : "Reading and recognizing…") }
            }
            #if os(iOS)
            .frame(maxWidth: 640, alignment: .leading).padding(PhonePageLayout.inset).frame(maxWidth: .infinity)
            #else
            .padding(24)
            #endif
        }
        .quickLookPreview($preview)
        .onChange(of: store.selectedFile?.metadata.id) { _, _ in page = 1; preview = nil }
        .task(id: ReadRequest(id: store.selectedFile?.metadata.id, page: page)) {
            read = nil; failure = nil; url = nil
            guard let id = store.selectedFile?.metadata.id else { failure = store.t("File is unavailable"); return }
            do {
                let localURL = try await store.localFileURL(id)
                try _Concurrency.Task.checkCancellation()
                url = localURL
                guard let files = store.fileCommands else { throw WorkspaceServiceError.unavailable }
                let result = try await files.readWorkspaceFile(id, startPage: page, pageCount: 1)
                try _Concurrency.Task.checkCancellation()
                read = result
            } catch is CancellationError { return }
            catch { failure = WorkspaceFileFailure.text(error, russian: ru) }
        }
    }
}
