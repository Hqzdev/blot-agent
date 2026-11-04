import BlotDesign
import BlotDomain
import Foundation
import QuickLook
import SwiftUI

enum WorkspaceExportFormat: String, CaseIterable { case markdown = "md", pdf, csv }

struct WorkspaceLocalFileView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var url: URL?
    @State private var preview: URL?
    @State private var text: String?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(store.selectedFile?.name ?? store.t("Files")).font(.title2).textSelection(.enabled)
                if let url {
                    HStack {
                        Button(store.t("Open file")) { preview = url }
                        ShareLink(item: url) { Text(store.t("Share")) }
                    }
                }
                if let text { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                else if let failure { Text(failure).foregroundStyle(WorkspaceStyle.secondary) }
                else { ProgressView() }
            }.padding(24)
        }
        .quickLookPreview($preview)
        .task(id: store.selectedFile?.metadata.id) {
            url = nil; text = nil; failure = nil
            guard let id = store.selectedFile?.metadata.id else { failure = store.t("File is unavailable"); return }
            do {
                url = try await store.localFileURL(id)
                text = try await store.localFileText(id)
            } catch { failure = store.t("File is unavailable") }
        }
    }
}
