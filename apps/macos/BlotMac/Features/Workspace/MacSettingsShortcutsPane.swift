import BlotDesign
import SwiftUI

struct MacSettingsShortcutsPane: View {
    @State private var search = ""
    private struct Shortcut: Identifiable {
        let title: String
        let detail: String
        let keys: String
        var id: String { title }
    }
    private let shortcuts: [Shortcut] = [
        .init(title: "Создать агента", detail: "Открыть создание нового специалиста.", keys: "⌘ N"),
        .init(title: "Настройки", detail: "Открыть настройки приложения.", keys: "⌘ ,"),
        .init(title: "Поиск", detail: "Поиск в пространстве или настройках.", keys: "⌘ K"),
        .init(title: "Назад", detail: "Вернуться из настроек или к предыдущему экрану.", keys: "⌘ ["),
        .init(title: "Отправить сообщение", detail: "Отправить введённый текст агенту.", keys: "⌘ ↵"),
        .init(title: "Закрыть меню", detail: "Отменить действие или выйти из настроек.", keys: "Esc")
    ]
    private var filtered: [Shortcut] {
        shortcuts.filter { search.isEmpty || ($0.title + $0.detail + $0.keys).localizedStandardContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск сочетаний клавиш", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Очистить поиск")
                }
            }.padding(.horizontal, 13).frame(height: 34)
                .background(MacTeamStyle.field, in: Capsule()).overlay(Capsule().strokeBorder(MacTeamSettingsStyle.edge))
            MacTeamSettingsSection(title: "") {
                ForEach(filtered) { item in
                    MacTeamSettingsRow(title: item.title, detail: item.detail) {
                        Text(item.keys).font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(WorkspaceStyle.ink.opacity(0.06), in: Capsule())
                    }
                    if item.id != filtered.last?.id { Divider() }
                }
                if filtered.isEmpty { MacTeamSettingsRow(title: "Ничего не найдено") { EmptyView() } }
            }
        }
    }
}
