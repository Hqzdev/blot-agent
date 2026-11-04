import BlotDesign
import BlotDomain
import SwiftUI

struct MacSettingsStoragePane: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var chatScope: ChatScope?
    private enum ChatScope: String, Identifiable { case all, archived; var id: String { rawValue } }
    private struct Segment: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }
    private var segments: [Segment] {
        let archived = Set(store.snapshot.conversations.filter(\.archived).map(\.metadata.id))
        let activeBytes = store.snapshot.messages.filter { !archived.contains($0.conversationId) }.reduce(Int64(0)) { $0 + Int64($1.content.utf8.count) }
        let archivedBytes = store.snapshot.messages.filter { archived.contains($0.conversationId) }.reduce(Int64(0)) { $0 + Int64($1.content.utf8.count) }
        return [.init(id: "Переписки", bytes: activeBytes, color: .yellow),
            .init(id: "Архив", bytes: archivedBytes, color: MacTeamSettingsStyle.accent),
            .init(id: "Документы", bytes: store.snapshot.artifacts.reduce(Int64(0)) { $0 + Int64($1.byteCount) }, color: .green)]
    }
    var body: some View {
        let content = segments
        let total = content.reduce(Int64(0)) { $0 + $1.bytes }
        VStack(alignment: .leading, spacing: 42) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("В этом пространстве").font(.system(size: 14, weight: .medium))
                    Text("Объём текста сообщений и сохранённых документов. Служебные данные и кэш не учитываются.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Text(bytes(total)).font(.system(size: 14, weight: .medium)).padding(.top, 6)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(content) { item in
                            item.color.frame(width: total > 0 ? geometry.size.width * Double(item.bytes) / Double(total) : 0)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkspaceStyle.ink.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 9))
                }.frame(height: 24).accessibilityLabel("Объём содержимого: " + bytes(total))
                HStack(alignment: .top, spacing: 28) {
                    ForEach(content) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 7) { Circle().fill(item.color).frame(width: 8, height: 8); Text(item.id) }
                            Text(bytes(item.bytes)).foregroundStyle(.secondary)
                        }.font(.system(size: 12))
                    }
                }
            }
            MacTeamSettingsSection(title: "") {
                MacTeamSettingsLink(title: "Управление переписками", detail: "Просмотрите чаты перед архивированием или удалением.", actionTitle: "Просмотреть") {
                    chatScope = .all
                }
            }
            MacTeamSettingsSection(title: "") {
                MacTeamSettingsLink(title: "Документы", detail: "Файлы пространства, вложения и результаты работы агентов.", actionTitle: "Открыть") {
                    store.settingsRoute = nil; store.navigate(.files)
                }
                Divider()
                MacTeamSettingsLink(title: "Архивированные чаты", detail: "Восстановите переписку или удалите её историю.", actionTitle: "Управлять") {
                    chatScope = .archived
                }
            }
        }.sheet(item: $chatScope) { scope in
            MacSettingsStoredChats(archivedOnly: scope == .archived).environment(store)
        }
    }
    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}

private struct MacSettingsStoredChats: View {
    @Environment(\.macSheetSize) private var sheetSize
    let archivedOnly: Bool
    @Environment(WorkspaceStore.self) private var store
    @State private var deleting: BlotV3.Conversation?
    private var chats: [BlotV3.Conversation] { store.snapshot.conversations.filter { !archivedOnly || $0.archived } }
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: archivedOnly ? "Архивированные чаты" : "Переписки")
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if chats.isEmpty { Text("Здесь пока нет переписок").foregroundStyle(.secondary).padding(40) }
                    ForEach(chats, id: \.metadata.id) { chat in
                        HStack(spacing: 14) {
                            Image(systemName: chat.archived ? "archivebox" : "bubble.left").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chat.title).lineLimit(1)
                                Text(chat.metadata.updatedAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button(chat.archived ? "Восстановить" : "В архив") { store.setChatArchived(chat.metadata.id, archived: !chat.archived) }
                                .buttonStyle(MacSettingsActionStyle())
                            Button(role: .destructive) { deleting = chat } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).accessibilityLabel("Удалить чат: " + chat.title)
                        }.padding(.vertical, 14)
                        Divider()
                    }
                }.padding(.horizontal, 24)
            }
            WorkspaceFeedback().padding(.horizontal, 24)
        }.frame(width: min(640, sheetSize.width), height: min(500, sheetSize.height))
            .background(MacTeamSettingsStyle.canvas).disabled(store.busy)
            .confirmationDialog("Удалить переписку?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { chat in
                Button("Удалить чат", role: .destructive) { store.deleteChat(chat.metadata.id); deleting = nil }
                Button("Отмена", role: .cancel) { deleting = nil }
            } message: { _ in Text("История сообщений будет удалена. Агент останется в команде.") }
    }
}
