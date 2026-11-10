import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceFilesImportButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var importing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { importing = true } label: {
                Label(store.language == "ru" ? "Импортировать файлы" : "Import files", systemImage: "square.and.arrow.down")
            }.disabled(store.busy || store.fileCommands == nil)
            WorkspaceFeedback()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard urls.count <= 32 else {
                    store.error = store.language == "ru" ? "Выберите не больше 32 файлов за один раз." : "Select at most 32 files at a time."
                    return
                }
                _Concurrency.Task { await store.importWorkspaceFiles(urls) }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
    }
}
