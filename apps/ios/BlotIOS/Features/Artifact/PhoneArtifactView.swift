import BlotAPI
import BlotDesign
import SwiftUI

/// Большой diff читается страницами; исходный артефакт остаётся неизменяемым на Mac.
struct PhoneArtifactView: View {
    let client: BackendClient
    let id: UUID
    @State private var offset = 0
    @State private var content = ""
    @State private var hasMore = false
    @State private var error: String?
    private let pageSize = 262_144
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BlotSpace.s12) {
                HStack(spacing: BlotSpace.s8) {
                    Button { offset = max(0, offset - pageSize) } label: { Label("Previous", systemImage: "chevron.left") }
                        .buttonStyle(PhoneButtonStyle()).disabled(offset == 0)
                    Spacer()
                    Text("Page \(offset / pageSize + 1)").blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
                    Spacer()
                    Button { offset += pageSize } label: { Label("Next", systemImage: "chevron.right") }
                        .buttonStyle(PhoneButtonStyle()).disabled(!hasMore)
                }
                if let error { PhoneErrorText(error) }
                Text(content).blotFont(.code).foregroundStyle(BlotColor.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BlotSpace.s12)
                    .blotPanel(fill: BlotColor.sidebar)
            }
            .padding(BlotSpace.panel)
        }
        .background(BlotColor.canvas)
        .phoneBars()
        .navigationTitle("Accepted changes")
        .task(id: offset) {
            do {
                let bytes = try await client.bytes("v2/artifacts/\(id.uuidString)/content?offset=\(offset)&length=\(pageSize)")
                content = String(decoding: bytes, as: UTF8.self); hasMore = bytes.count == pageSize; error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
