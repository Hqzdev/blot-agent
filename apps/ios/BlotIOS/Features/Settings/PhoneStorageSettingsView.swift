import BlotDomain
import BlotDesign
import SwiftUI

struct PhoneStorageSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    private struct Segment: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }
    private var segments: [Segment] {
        let archived = Set(store.snapshot.conversations.filter(\.archived).map(\.metadata.id))
        let activeBytes = store.snapshot.messages.filter { !archived.contains($0.conversationId) }.reduce(Int64(0)) { $0 + Int64($1.content.utf8.count) }
        let archivedBytes = store.snapshot.messages.filter { archived.contains($0.conversationId) }.reduce(Int64(0)) { $0 + Int64($1.content.utf8.count) }
        return [.init(id: "Conversations", bytes: activeBytes, color: .yellow),
                .init(id: "Archive", bytes: archivedBytes, color: PhoneSettingsStyle.accent),
                .init(id: "Documents", bytes: store.snapshot.artifacts.reduce(Int64(0)) { $0 + Int64($1.byteCount) }, color: .green)]
    }
    var body: some View {
        let content = segments
        let total = content.reduce(Int64(0)) { $0 + $1.bytes }
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "In this workspace", detail: "Message text and saved documents. Internal data and cache are excluded.") {
                VStack(alignment: .leading, spacing: 20) {
                    Text(bytes(total)).font(.title3.weight(.medium)).monospacedDigit()
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(content) { item in
                                item.color.frame(width: total > 0 ? geometry.size.width * Double(item.bytes) / Double(total) : 0)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .background(WorkspaceStyle.ink.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 7))
                    }.frame(height: 20).accessibilityHidden(true)
                    ForEach(content) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            Text(store.settingsText(item.id))
                            Spacer()
                            Text(bytes(item.bytes)).foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }
                }.padding(16)
            }
            PhoneSettingsGroup(title: "") {
                link("Manage conversations", detail: "Review chats before archiving or deleting.", route: .chats)
                PhoneSettingsDivider()
                link("Documents", detail: "Workspace files, attachments and agent results.", route: .files)
                PhoneSettingsDivider()
                link("Archived chats", detail: "Restore a conversation or delete its history.", route: .archivedChats)
            }
        }
    }
    private func link(_ title: String, detail: String, route: WorkspaceRoute) -> some View {
        Button { store.navigate(route) } label: { PhoneSettingsRow(title: title, detail: detail) }.buttonStyle(.plain)
    }
    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}
