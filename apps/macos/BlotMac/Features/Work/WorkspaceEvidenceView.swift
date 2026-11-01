import BlotAPI
import BlotDesign
import SwiftUI

struct WorkspaceEvidence: Identifiable {
    let kind: String
    let id: UUID
}

/// Read-only view of one backend record (the evidence behind a status, a graph edge or an artifact).
struct WorkspaceEvidenceView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let evidence: WorkspaceEvidence

    private var title: String {
        evidence.kind.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
    }

    var body: some View {
        KSheet(title, subtitle: "Record from the Blot server", width: 760) {
            if let row = app.workspace.find(evidence.kind, evidence.id) {
                VStack(alignment: .leading, spacing: 6) {
                    KeyValueRow(label: "ID", value: evidence.id.uuidString, mono: true)
                    KeyValueRow(label: "Version", value: String(row.version))
                    KeyValueRow(label: "Updated", value: WorkspaceDate.display(row.updatedAt))
                }
                CodeBlock(title: "data", icon: "code", text: row.data.formatted, maxHeight: 280)
                if evidence.kind == "ARTIFACT" { ArtifactContentView(id: row.id) }
            } else {
                EmptyState(icon: "circle-alert", title: "Record unavailable",
                           detail: "It was deleted or is no longer shared with this account.")
            }
        } footer: {
            KButton(title: "Done", kind: .primary) { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .frame(minHeight: 440)
    }
}

/// Opens an artifact record in a sheet.
struct ArtifactLink: View {
    let id: UUID
    @State private var showing = false
    var body: some View {
        KButton(title: "Open artifact · " + String(id.uuidString.prefix(8)), icon: "file-text", height: 28) { showing = true }
            .sheet(isPresented: $showing) {
                WorkspaceEvidenceView(evidence: WorkspaceEvidence(kind: "ARTIFACT", id: id))
            }
    }
}

/// Artifact bytes, read 64 KiB at a time. Patches are shown as a diff.
private struct ArtifactContentView: View {
    let id: UUID
    @State private var bytes = Data()
    @State private var end = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !bytes.isEmpty {
                let text = String(decoding: bytes, as: UTF8.self)
                if text.hasPrefix("diff --git ") {
                    let lines = UnifiedDiffParser.parse(text)
                    DiffView(
                        file: ReviewFile(
                            path: id.uuidString + ".patch", added: lines.filter { $0.tone == .added }.count,
                            removed: lines.filter { $0.tone == .removed }.count, patch: text)
                    ).frame(minHeight: 220)
                } else {
                    CodeBlock(title: "content", icon: "file-text", text: text, maxHeight: 240)
                }
                Text("\(Int64(bytes.count).formatted(.byteCount(style: .file))) read" + (end ? " · complete" : " · more available"))
                    .font(KFont.caption()).foregroundStyle(K.text3)
            }
            if let error { InlineFeedback(text: error, tone: .error) }
            if !end {
                KButton(title: bytes.isEmpty ? "Load content" : "Load next 64 KB", icon: "arrow.down",
                        loading: busy) { load() }
            }
        }
    }
    private func load() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let part = try await BackendRuntime.shared.client.bytes(
                    "v2/artifacts/\(id.uuidString)/content?offset=\(bytes.count)&length=65536")
                bytes.append(part)
                end = part.count < 65536
            } catch { self.error = error.localizedDescription }
        }
    }
}
