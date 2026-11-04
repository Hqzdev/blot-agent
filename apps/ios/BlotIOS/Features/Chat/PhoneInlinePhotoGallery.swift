import BlotDesign
import PhotosUI
import SwiftUI

struct PhoneInlinePhotoGallery: View {
    @Bindable var menu: PhoneComposerMenuState
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var allPhotosVisible = false
    @State private var librarySelection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $menu.photos, selectionBehavior: .continuousAndOrdered,
                     matching: .images, preferredItemEncoding: .current) {
            EmptyView()
        }
        .photosPickerStyle(.inline)
        .photosPickerAccessoryVisibility(.hidden, edges: .all)
        .photosPickerDisabledCapabilities([.selectionActions, .collectionNavigation, .search])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { controls.padding(.horizontal, 20).padding(.bottom, 22) }
        .photosPicker(isPresented: $allPhotosVisible, selection: $librarySelection,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: allPhotosVisible) { _, visible in
            guard !visible, !librarySelection.isEmpty else { return }
            withKAnimation(reduceMotion, KMotion.panel) {
                menu.photos = librarySelection
                menu.attachPhotos()
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                Button {
                    withKAnimation(reduceMotion, KMotion.panel) { menu.page = .sources }
                } label: {
                    BlotIcon(symbol: "chevron.left", size: 22).frame(width: 46, height: 46)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .glassEffect(.regular.tint(.black.opacity(0.85)).interactive(), in: .circle)
                .accessibilityLabel(store.t("Back"))

                Spacer(minLength: 0)

                if menu.photos.isEmpty {
                    Button {
                        librarySelection = []
                        allPhotosVisible = true
                    } label: {
                        Text(store.t("All photos")).font(.body.weight(.semibold))
                            .padding(.horizontal, 20).frame(minHeight: 46)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .glassEffect(.regular.tint(.black.opacity(0.85)).interactive(), in: .capsule)
                } else {
                    Button {
                        withKAnimation(reduceMotion, KMotion.panel) { menu.attachPhotos() }
                    } label: {
                        Text(addTitle).font(.body.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 46)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
                }
            }
        }
    }

    private var addTitle: String {
        let count = menu.photos.count
        guard store.language == "ru" else { return "Add \(count) \(count == 1 ? "photo" : "photos")" }
        let ending: String
        if (11...14).contains(count % 100) { ending = "фотографий" }
        else {
            switch count % 10 {
            case 1: ending = "фотографию"
            case 2...4: ending = "фотографии"
            default: ending = "фотографий"
            }
        }
        return "Добавить \(count) \(ending)"
    }
}
