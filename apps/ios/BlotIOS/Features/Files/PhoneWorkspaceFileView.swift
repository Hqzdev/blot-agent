import BlotDesign
import BlotDomain
import Foundation
import QuickLook
import SwiftUI
import UIKit

struct PhoneWorkspaceFileView: View {
    private enum Content { case loading, text(String, Bool), preview(URL), unavailable }
    @Environment(WorkspaceStore.self) private var store
    @State private var content = Content.loading
    @State private var url: URL?

    var body: some View {
        Group {
            switch content {
            case .loading: ProgressView()
            case .text(let text, let isCode):
                ScrollView {
                    Text(text).font(isCode ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
            case .preview(let url): PhoneQuickLookFile(url: url)
            case .unavailable:
                ContentUnavailableView {
                    BlotLabel(store.t("File is unavailable"), symbol: "doc.badge.ellipsis", size: 44)
                } description: {
                    Text(store.t("The file is not stored on this iPhone. Connect the computer that contains it."))
                } actions: {
                    Button(store.t("Computers")) { store.navigate(.devices) }
                    Button(store.t("Retry")) { _Concurrency.Task { await load() } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let url {
                ShareLink(item: url) { BlotLabel(store.t("Share"), symbol: "square.and.arrow.up") }
                    .buttonStyle(WorkspaceButtonStyle(.secondary)).padding(PhonePageLayout.inset)
            }
        }
        .task(id: store.selectedFile?.metadata.id) { await load() }
    }

    private func load() async {
        content = .loading; url = nil
        guard let file = store.selectedFile, let fileURL = PhoneWorkspaceFiles.url(for: file) else {
            content = .unavailable; return
        }
        url = fileURL
        let ext = fileURL.pathExtension.lowercased()
        let kind = PhoneFileKind(name: file.name, mediaType: file.mediaType)
        if kind == .code || ["md", "markdown", "txt", "csv", "tsv"].contains(ext) {
            do {
                let text = try await _Concurrency.Task.detached(priority: .userInitiated) {
                    try String(contentsOf: fileURL, encoding: .utf8)
                }.value
                try _Concurrency.Task.checkCancellation()
                content = .text(text, kind == .code || kind == .spreadsheet)
            } catch is CancellationError { return }
            catch { content = .preview(fileURL) }
        } else { content = .preview(fileURL) }
    }
}

private struct PhoneQuickLookFile: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url { context.coordinator.url = url; controller.reloadData() }
    }

    @MainActor final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
