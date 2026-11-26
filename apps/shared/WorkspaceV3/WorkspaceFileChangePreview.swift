import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspaceFileChangePreview: View {
    let id: UUID
    @Environment(WorkspaceStore.self) private var store
    @State private var name = ""
    @State private var text: String?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                BlotIcon(symbol: "doc.text", size: 18)
                Text(name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                Spacer(minLength: 4)
            }
            if let text {
                ScrollView {
                    Text(text).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            } else if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
            else { ProgressView().controlSize(.small) }
            Spacer(minLength: 0)
        }.padding(20).background(WorkspaceStyle.canvas)
            .accessibilityIdentifier("workspace.chat.file-preview")
            .task(id: id) {
                do {
                    guard let files = store.fileCommands else { throw WorkspaceServiceError.unavailable }
                    name = (try await files.workspaceFileChange(id)).path
                    text = try await files.readWorkspaceFileChange(id)
                } catch { self.error = store.language == "ru" ? "Не удалось прочитать файл. Проверьте доступ к исходной папке." : "Could not read the file. Check access to its original folder." }
            }
    }
}
