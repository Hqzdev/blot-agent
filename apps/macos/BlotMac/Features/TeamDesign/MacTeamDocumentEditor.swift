import BlotDesign
import SwiftUI
import UniformTypeIdentifiers

private struct MacTeamTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct MacTeamDocumentEditor: View {
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var title = ""
    @State private var text = ""
    @State private var exporting = false
    @State private var status: String?
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: "Документ")
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    MacTeamFileIcon(filename: title)
                    TextField("Название документа", text: $title).font(.system(size: 19, weight: .medium))
                }
                HStack {
                    Text(presentation.document.map { presentation.agent(for: $0.agentID).name } ?? "Blot")
                        .foregroundStyle(.secondary)
                    Spacer()
                    MacTeamBadge(
                        text: presentation.document?.published == true ? "Сохранён в демо-рассылках" : "Черновик")
                }
                TextEditor(text: $text).font(.system(size: 14)).lineSpacing(6).scrollContentBackground(.hidden).frame(
                    height: 320
                )
                .padding(12).background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: 16))
                if let status { BlotLabel(status, symbol: "checkmark.circle", size: BlotIconSize.inline).foregroundStyle(.secondary) }
            }.font(.system(size: 12)).padding(24)
            Divider()
            HStack {
                Button("Экспорт .txt") { exporting = true }.buttonStyle(WorkspaceButtonStyle(.secondary))
                Spacer()
                Button("Сохранить") { save(publish: false) }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(
                    title.isEmpty)
                Button("В демо-рассылку") { save(publish: true) }.buttonStyle(WorkspaceButtonStyle()).disabled(
                    title.isEmpty || text.isEmpty)
            }.padding(18)
        }.frame(width: 720)
            .onAppear {
                title = presentation.document?.title ?? ""
                text = presentation.document?.body ?? ""
            }
            .fileExporter(
                isPresented: $exporting, document: MacTeamTextDocument(text: text), contentType: .plainText,
                defaultFilename: (title as NSString).deletingPathExtension
            ) { result in
                switch result {
                case .success: status = "Файл сохранён на Mac"
                case .failure: status = "Не удалось сохранить файл"
                }
            }
    }
    private func save(publish: Bool) {
        let id = presentation.selectedDocumentID
        presentation.demo.update { state in
            guard let index = state.documents.firstIndex(where: { $0.id == id }) else { return }
            state.documents[index].title = title
            state.documents[index].body = text
            if publish { state.documents[index].published = true }
        }
        status =
            publish ? "Материал сохранён в демо-рассылках. Внешняя публикация не выполнялась." : "Изменения сохранены"
    }
}

struct MacTeamBillingPanel: View {
    @Environment(MacTeamPresentation.self) private var presentation
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: "Демо-подписка")
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                Text("Выберите план для демонстрации").font(.system(size: 22, weight: .medium))
                Text("Платежи не подключены. Выбор меняет только лимит демо-действий и отображение использования.")
                    .foregroundStyle(.secondary).lineSpacing(4)
                ForEach([("Free", 50), ("Pro", 100), ("Team", 500)], id: \.0) { name, limit in
                    MacTeamNavigationButton(selected: presentation.settings.plan == name) {
                        presentation.settings.plan = name
                        presentation.settings.weeklyLimit = limit
                    } label: {
                        HStack {
                            Text(name).fontWeight(.semibold)
                            Spacer()
                            Text("\(limit) действий / неделю").foregroundStyle(.secondary)
                            if presentation.settings.plan == name { BlotIcon(symbol: "checkmark", size: BlotIconSize.inline) }
                        }
                    }
                }
            }.font(.system(size: 13)).padding(26)
        }.frame(width: 560)
    }
}
