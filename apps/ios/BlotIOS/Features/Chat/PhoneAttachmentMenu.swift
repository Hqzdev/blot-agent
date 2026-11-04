import BlotDesign
import Observation
import PhotosUI
import SwiftUI

enum PhoneAttachmentSource: String, CaseIterable, Identifiable {
    case camera, photos, files, plugins
    var id: String { rawValue }
    var title: String {
        switch self { case .camera: "Camera"; case .photos: "Photo"; case .files: "Files"; case .plugins: "Plug-ins" }
    }
    var symbol: String {
        switch self { case .camera: "camera"; case .photos: "photo.on.rectangle"; case .files: "paperclip"; case .plugins: "puzzlepiece.extension" }
    }
}

struct PhoneAttachmentMenu: View {
    let onSelect: (PhoneAttachmentSource) -> Void
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(spacing: 4) {
            ForEach(PhoneAttachmentSource.allCases) { source in
                Button { onSelect(source) } label: {
                    HStack(spacing: 14) {
                        BlotIcon(symbol: source.symbol, size: 23).font(.system(size: 21))
                            .frame(width: 42, height: 42)
                            .background(WorkspaceStyle.surface, in: Circle())
                        Text(store.t(source.title)).font(.title3)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 60).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(store.t(source.title))
            }
        }
        .padding(16)
        .foregroundStyle(WorkspaceStyle.ink)
    }
}

@MainActor @Observable
final class PhoneComposerMenuState {
    enum Page { case sources, photos }

    struct Request: Identifiable {
        let id = UUID()
        let source: PhoneAttachmentSource
        var photos: [PhotosPickerItem] = []
    }

    var page: Page?
    var photos: [PhotosPickerItem] = []
    private(set) var request: Request?
    var isOpen: Bool { page != nil }

    func open() {
        photos = []
        page = .sources
    }

    func select(_ source: PhoneAttachmentSource) {
        if source == .photos { page = .photos }
        else {
            request = Request(source: source)
            dismiss()
        }
    }

    func attachPhotos() {
        guard !photos.isEmpty else { return }
        request = Request(source: .photos, photos: photos)
        dismiss()
    }

    func dismiss() {
        page = nil
        photos = []
    }
}
