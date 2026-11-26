import BlotWorkspace
import BlotDesign
import SwiftUI

struct WorkspaceTableEditor: View {
    @Bindable var session: WorkspaceDocumentEditSession
    @Environment(WorkspaceStore.self) private var store
    private var ru: Bool { store.language == "ru" }
    private let pageSize = 20
    private var start: Int { min(session.tablePage * pageSize, max(0, session.draft.rows.count - 1) / pageSize * pageSize) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { session.draft.rows.append(Array(repeating: "", count: session.draft.columns.count)); session.tablePage = max(0, session.draft.rows.count - 1) / pageSize } label: { BlotLabel(ru ? "Строка" : "Row", symbol: "plus") }
                    .disabled(session.draft.rows.count >= 10_000)
                Button { session.draft.columns.append(""); for index in session.draft.rows.indices { session.draft.rows[index].append("") } } label: { BlotLabel(ru ? "Столбец" : "Column", symbol: "plus") }
                    .disabled(session.draft.columns.count >= 100)
                Spacer()
                Text("\(session.draft.rows.count) × \(session.draft.columns.count)").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(WorkspaceButtonStyle(.secondary))
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Color.clear.frame(width: 34, height: 1)
                        ForEach(session.draft.columns.indices, id: \.self) { column in
                            VStack(spacing: 6) {
                                cell($session.draft.columns[column], label: (ru ? "Заголовок столбца " : "Column header ") + String(column + 1), header: true)
                                Button { removeColumn(column) } label: { BlotLabel(ru ? "Удалить столбец" : "Remove column", symbol: "minus") }.font(.caption)
                                    .buttonStyle(WorkspaceButtonStyle(.quiet)).disabled(session.draft.columns.count <= 1)
                            }.frame(width: 168)
                        }
                    }
                    ForEach(start..<min(start + pageSize, session.draft.rows.count), id: \.self) { row in
                        HStack(alignment: .top, spacing: 6) {
                            Button { session.draft.rows.remove(at: row) } label: { BlotIcon(symbol: "minus", size: 14).frame(width: 34, height: 42).contentShape(Rectangle()) }
                                .buttonStyle(.plain).accessibilityLabel((ru ? "Удалить строку " : "Remove row ") + String(row + 1))
                            ForEach(session.draft.columns.indices, id: \.self) { column in
                                cell($session.draft.rows[row][column], label: (ru ? "Ячейка " : "Cell ") + "\(row + 1),\(column + 1)", header: false)
                            }
                        }
                    }
                }.padding(2)
            }
            if session.draft.rows.count > pageSize {
                HStack {
                    Button(ru ? "Назад" : "Previous") { session.tablePage = max(0, session.tablePage - 1) }.disabled(start == 0)
                    Text("\(start + 1)–\(min(start + pageSize, session.draft.rows.count)) / \(session.draft.rows.count)").font(.caption)
                    Button(ru ? "Далее" : "Next") { session.tablePage += 1 }.disabled(start + pageSize >= session.draft.rows.count)
                }.buttonStyle(WorkspaceButtonStyle(.secondary))
            }
        }
    }
    private func cell(_ text: Binding<String>, label: String, header: Bool) -> some View {
        TextField("", text: text).textFieldStyle(.plain).font(header ? .body.weight(.semibold) : .body)
            .padding(12).frame(width: 168)
            .background(WorkspaceStyle.ink.opacity(header ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.ink.opacity(0.08)))
            .accessibilityLabel(label)
    }
    private func removeColumn(_ index: Int) {
        session.draft.columns.remove(at: index)
        for row in session.draft.rows.indices { session.draft.rows[row].remove(at: index) }
    }
}
