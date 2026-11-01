import AppKit
import BlotDesign
import SwiftUI
import UniformTypeIdentifiers

struct ProjectSourceRow: View {
    @Environment(AppState.self) private var app
    let source: ProjectSource
    @State private var thumbnail: NSImage?

    private var type: UTType? { UTType(filenameExtension: URL(fileURLWithPath: source.path).pathExtension) }
    private var isImage: Bool { type?.conforms(to: .image) == true }

    var body: some View {
        Button { app.shell.previewSource = source } label: {
            HStack(spacing: 12) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        KIcon(isImage ? "photo" : type == .pdf ? "doc.richtext" : "doc.text", size: 18, color: K.text3)
                    }
                }.frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
                Text(source.name).font(KFont.body()).foregroundStyle(K.text2).lineLimit(1)
                    .truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 32).contentShape(Rectangle()).kHover(radius: K.rSm)
        }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm).help(source.path)
            .task(id: source.id) {
                thumbnail = nil
                guard isImage, let url = source.url else { return }
                let data = try? await Task.detached(priority: .utility) {
                    try LocalPreviewReader.read(url, maxBytes: 10 * 1024 * 1024)
                }.value
                guard !Task.isCancelled, let data else { return }
                thumbnail = NSImage(data: data)
            }
    }
}
