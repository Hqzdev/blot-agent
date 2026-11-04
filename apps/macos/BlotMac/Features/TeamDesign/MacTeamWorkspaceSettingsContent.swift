import BlotDesign
import SwiftUI
import UniformTypeIdentifiers

struct MacTeamWorkspaceSettingsContent: View {
    let pane: MacTeamSettingsPane
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var exporting = false
    @State private var exportDocument: MacTeamWorkspaceExport?
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            switch pane {
            case .memory: memory
            case .storage: storage
            case .privacy: privacy
            default: EmptyView()
            }
            if let status { Text(status).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "Blot-workspace") { result in
            switch result {
            case .success: status = "Копия пространства сохранена на Mac."
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { status = "Не удалось сохранить копию: " + error.localizedDescription }
            }
        }
    }

    @ViewBuilder private var memory: some View {
        let shared = presentation.demo.state.memories.filter { $0.agentID == nil }
        let personal = presentation.demo.state.memories.filter { $0.agentID != nil }
        MacTeamSettingsSection(title: "Контекст команды") {
            MacTeamSettingsRow(title: "Общая память", detail: "Воспоминания, доступные всей команде.") {
                Text("\(shared.count)").foregroundStyle(.secondary)
            }
            Divider()
            MacTeamSettingsRow(title: "Память агентов", detail: "Отдельные инструкции и контекст специалистов.") {
                Text("\(personal.count)").foregroundStyle(.secondary)
            }
            Divider()
            MacTeamSettingsLink(title: "Управление памятью", detail: "Просматривайте, изменяйте и добавляйте воспоминания.", actionTitle: "Открыть") {
                presentation.open(.library(.memory))
                presentation.closeSettings()
            }
        }
        MacTeamSettingsSection(title: "Как запоминать") {
            MacTeamSettingsRow(title: "Из разговора", detail: "Напишите агенту «Запомни…». Для общей памяти добавьте «для всех».") {
                BlotIcon(.memory, size: BlotIconSize.navigation).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var storage: some View {
        MacTeamSettingsSection(title: "На этом Mac") {
            MacTeamSettingsRow(title: "Документы") { Text("\(presentation.demo.state.documents.count)").foregroundStyle(.secondary) }
            Divider()
            MacTeamSettingsRow(title: "Переписки") { Text("\(presentation.demo.state.threads.count)").foregroundStyle(.secondary) }
            Divider()
            MacTeamSettingsRow(title: "Сообщения") {
                Text("\(presentation.demo.state.threads.values.reduce(0) { $0 + $1.count })").foregroundStyle(.secondary)
            }
            Divider()
            MacTeamSettingsLink(title: "Файлы пространства", detail: "Документы агентов, черновики и результаты задач.", actionTitle: "Открыть") {
                presentation.open(.library(.files))
                presentation.closeSettings()
            }
        }
        MacTeamSettingsSection(title: "Резервная копия") {
            MacTeamSettingsLink(title: "Экспортировать пространство",
                               detail: "JSON-файл с агентами, переписками, документами и настройками.", actionTitle: "Экспорт") {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    exportDocument = MacTeamWorkspaceExport(data: try encoder.encode(presentation.demo.state))
                    exporting = true
                } catch { status = "Не удалось подготовить копию: " + error.localizedDescription }
            }
        }
    }

    @ViewBuilder private var privacy: some View {
        MacTeamSettingsSection(title: "Хранение и выполнение") {
            MacTeamSettingsRow(title: "Локальное пространство", detail: "История и предпочтения сохраняются на этом Mac между запусками.") {
                MacTeamBadge(text: "Локально")
            }
            Divider()
            MacTeamSettingsRow(title: "Действия в сервисах", detail: "Отправка писем, публикации и покупки воспроизводятся в демо.") {
                MacTeamBadge(text: "Демо")
            }
        }
        MacTeamSettingsSection(title: "Разрешения аккаунтов") {
            ForEach(presentation.plugins.filter { !$0.accounts.isEmpty }) { plugin in
                MacTeamSettingsRow(title: plugin.name, detail: "Аккаунтов: \(plugin.accounts.count). Чтение, черновики и отправка настраиваются отдельно.") {
                    Button("Настроить") { presentation.sheet = .plugin(plugin) }.buttonStyle(WorkspaceButtonStyle(.secondary))
                }
                if plugin.id != presentation.plugins.last(where: { !$0.accounts.isEmpty })?.id { Divider() }
            }
        }
    }
}

private struct MacTeamWorkspaceExport: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
