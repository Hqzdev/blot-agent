import AppKit
import PDFKit
import BlotDesign
import SwiftUI

struct SourcePreview: View {
    @Environment(AppState.self) private var app
    let source: ProjectSource
    @State private var text: String?
    @State private var image: NSImage?
    @State private var pdf: PDFDocument?
    @State private var error: String?
    @State private var loadedSourceID: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconButton(icon: "chevron-left", help: "Back to project") { app.shell.previewSource = nil }
                Text(source.name).font(KFont.label()).foregroundStyle(K.text).lineLimit(1)
                Spacer()
                if let text { CopyButton(text: text, title: "Copy file") }
            }
            if source.url == nil {
                EmptyState(icon: "file-text", title: "No local copy", detail: "This path comes from a run. Add the file from your Mac, or open the run artifact from Results.")
            } else if loadedSourceID != source.id {
                VStack(spacing: 24) {
                    SkeletonBlock().frame(height: 160)
                    SkeletonText(lines: 5)
                    Spacer()
                }.accessibilityElement(children: .ignore).accessibilityLabel("Loading file preview")
            } else if let image {
                ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 500) }
            } else if let pdf { LocalPDFPreview(document: pdf) }
            else if let text {
                ScrollView([.horizontal, .vertical]) {
                    Text(text).font(KFont.mono(12)).foregroundStyle(K.text2).lineSpacing(3).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }.kCard(radius: K.rLg, fill: K.surface)
            } else if let error {
                EmptyState(icon: "circle-alert", title: "Cannot preview this file", detail: error)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: KSpace.sm) {
                Text(source.path).font(KFont.mono(10)).foregroundStyle(K.text3).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                CopyButton(text: source.path, title: "Copy path")
            }
        }.padding(16).frame(maxHeight: .infinity).background(K.bg)
        .loadingTransition(isLoading: source.url != nil && loadedSourceID != source.id)
        .task(id: source.id) { await load() }
    }
    private func load() async {
        text = nil; image = nil; pdf = nil; error = nil
        loadedSourceID = nil
        guard let url = source.url else { return }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try LocalPreviewReader.read(url, maxBytes: 10 * 1024 * 1024)
            }.value
            guard !Task.isCancelled else { return }
            if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(data: data) { pdf = document }
            else if let value = NSImage(data: data) { image = value }
            else if let value = String(data: data, encoding: .utf8) { text = String(value.prefix(256 * 1024)) }
            else { error = LocalPreviewError.unsupported.localizedDescription }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        loadedSourceID = source.id
    }
}

private struct LocalPDFPreview: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; return view }
    func updateNSView(_ view: PDFView, context: Context) { view.document = document }
}
