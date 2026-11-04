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
        return HStack(spacing: 10) {
            BlotIcon(symbol: "magnifyingglass").foregroundStyle(WorkspaceStyle.secondary)
            TextField(store.t("Search files"), text: $navigation.filesQuery)
                .textFieldStyle(.plain).autocorrectionDisabled().textInputAutocapitalization(.never)
                .submitLabel(.search).accessibilityLabel(store.t("Search files"))
            if !store.navigation.filesQuery.isEmpty {
                Button { store.navigation.filesQuery = "" } label: {
                    BlotIcon(symbol: "xmark.circle.fill", size: 17).foregroundStyle(WorkspaceStyle.secondary)
                }.buttonStyle(.plain).accessibilityLabel(store.t("Clear search"))
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
