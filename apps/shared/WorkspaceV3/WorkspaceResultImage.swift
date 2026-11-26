import BlotDesign
import BlotDomain
import ImageIO
import SwiftUI

struct WorkspaceResultImage: View {
    let file: BlotV3.Artifact
    @Environment(WorkspaceStore.self) private var store
    @State private var thumbnail: CGImage?
    var body: some View {
        Button { store.showGeneratedFile(file.metadata.id) } label: {
            Group {
                if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFit() }
                else { Text(file.name).font(.caption).foregroundStyle(.secondary).padding(12) }
            }.frame(maxWidth: .infinity).frame(height: 120)
                .background(WorkspaceStyle.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14)).contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityLabel((store.language == "ru" ? "Открыть изображение " : "Open image ") + file.name)
            .task(id: file.hash) {
                guard let url = try? await store.localFileURL(file.metadata.id) else { return }
                thumbnail = await _Concurrency.Task.detached(priority: .utility) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 480, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
                }.value
            }
    }
}
