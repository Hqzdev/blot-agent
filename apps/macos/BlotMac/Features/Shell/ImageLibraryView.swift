import BlotDesign
import SwiftUI
import UniformTypeIdentifiers

struct ImageLibraryView: View {
    @Environment(AppState.self) private var app
    @State private var importing = false
    @State private var error: String?
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: KSpace.xl) {
                PageHeader(title: "Images", subtitle: "Images saved in your workspace on this Mac.") {
                    KButton(title: "Import images", icon: "plus") { importing = true }
                }
                if app.workspaceLibrary.images.isEmpty {
                    EmptyState(icon: WorkspaceTool.images.icon, title: "Your image library",
                                       detail: "Import images to browse and preview them here.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 20) {
                        ForEach(app.workspaceLibrary.images) { image in
                            LibraryImageCell(item: image) { app.workspaceLibrary.removeImage(image.id) }
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            do { try app.workspaceLibrary.importImages(result.get()) }
            catch { self.error = error.localizedDescription }
        }
        .alert("Could not import images", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct LibraryImageCell: View {
    let item: LibraryImage
    let remove: () -> Void
    @State private var image: NSImage?
    @State private var error: String?
    @State private var previewing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { previewing = true } label: {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFit() }
                    else if error != nil { KIcon("photo", size: 28, color: K.text3) }
                    else { SkeletonBlock() }
                }.frame(maxWidth: .infinity).frame(height: 150)
                    .background(K.surface2, in: RoundedRectangle(cornerRadius: K.rLg, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: K.rLg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: K.rLg, style: .continuous).strokeBorder(K.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }.buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm).disabled(image == nil).accessibilityLabel("Preview \(item.name)")
            Text(item.name).font(KFont.ui(13)).foregroundStyle(K.text).lineLimit(1)
            if let error { Text(error).font(KFont.caption()).foregroundStyle(K.text2).lineLimit(2) }
        }
        .loadingTransition(isLoading: image == nil && error == nil)
        .task(id: item.id) {
            do {
                let data = try await Task.detached(priority: .userInitiated) { try item.previewData() }.value
                guard !Task.isCancelled else { return }
                guard let image = NSImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                self.image = image
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
        .contextMenu { Button("Remove from library", role: .destructive, action: remove) }
        .sheet(isPresented: $previewing) {
            KSheet(item.name, width: 700) {
                if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 500) }
            } footer: {
                KButton(title: "Remove from library", icon: "trash-2", kind: .danger) { previewing = false; remove() }
                KButton(title: "Done", kind: .primary) { previewing = false }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
