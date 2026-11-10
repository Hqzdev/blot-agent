import BlotDesign
import BlotDomain
import Foundation
import SwiftUI

struct PhoneFilesContent: View {
    @Environment(WorkspaceStore.self) private var store

    private var query: String { store.navigation.filesQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var files: [BlotV3.Artifact] {
        store.snapshot.artifacts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let visibleFiles = files
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceHeading(title: "Files", subtitle: "Workspace results and documents")
            WorkspaceFilesImportButton()
            search
            if visibleFiles.isEmpty {
                if query.isEmpty { WorkspaceDataState(state: .empty) }
                else {
                    ContentUnavailableView {
                        BlotLabel(store.t("No results"), symbol: "magnifyingglass", size: 44)
                    } description: { Text(query) }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleFiles, id: \.metadata.id) { file in
                        Button {
                            store.selectedRecordID = file.metadata.id
                            store.navigate(.file)
                        } label: { PhoneFileRow(file: file) }
                            .buttonStyle(.plain)
                        if file.metadata.id != visibleFiles.last?.metadata.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
            Text(store.t("Files stay on this computer. Results are available on linked devices."))
                .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
        }
    }

    private var search: some View {
        @Bindable var navigation = store.navigation
        return PhonePageSearchField(placeholder: store.t("Search files"), text: $navigation.filesQuery)
    }
}
