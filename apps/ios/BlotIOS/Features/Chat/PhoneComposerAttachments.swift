import BlotDesign
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct PhoneComposerAttachments: View {
    @Binding var urls: [URL]
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var thumbnails = PhoneAttachmentThumbnails()
    @State private var preview: URL?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(urls, id: \.self) { url in
                    if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                        photo(url)
                    } else {
                        file(url)
                    }
                }
            }.padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .quickLookPreview($preview)
        .onChange(of: urls) { _, urls in
            if let preview, !urls.contains(preview) { self.preview = nil }
        }
    }

    private func photo(_ url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { preview = url } label: {
                PhoneAttachmentThumbnail(url: url, thumbnails: thumbnails)
            }.buttonStyle(.plain).accessibilityLabel(store.t("Photo") + ": " + url.lastPathComponent)

            Button { remove(url) } label: {
                BlotIcon(.close, size: 12)
                    .foregroundStyle(BlotColor.onInverse)
                    .frame(width: 24, height: 24)
                    .background(BlotColor.inverse.opacity(0.75), in: Circle())
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(store.t("Remove attachment") + ": " + url.lastPathComponent)
        }
    }

    private func file(_ url: URL) -> some View {
        HStack(spacing: 0) {
            Button { preview = url } label: {
                BlotLabel(url.lastPathComponent, symbol: "doc", size: 18)
                    .font(.caption).lineLimit(1).frame(maxWidth: 180, minHeight: 44)
                    .padding(.leading, 12)
            }.buttonStyle(.plain)
            Button { remove(url) } label: {
                BlotIcon(.close, size: 14).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(store.t("Remove attachment") + ": " + url.lastPathComponent)
        }
        .foregroundStyle(WorkspaceStyle.ink)
        .background(WorkspaceStyle.surface, in: Capsule())
    }

    private func remove(_ url: URL) {
        withKAnimation(reduceMotion) { urls.removeAll { $0 == url } }
    }
}

private struct PhoneAttachmentThumbnail: View {
    let url: URL
    let thumbnails: PhoneAttachmentThumbnails
    @State private var image: CGImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            WorkspaceStyle.surface
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if loaded {
                BlotIcon(symbol: "photo", size: 28).foregroundStyle(WorkspaceStyle.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: url) {
            let thumbnail = await thumbnails.image(for: url)
            guard !Task.isCancelled else { return }
            image = thumbnail
            loaded = true
        }
    }
}
