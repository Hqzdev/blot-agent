import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

nonisolated struct WorkspaceChangesSource: Hashable, Sendable {
    enum Kind: String, Sendable { case draft, creation, fileWrite }

    let kind: Kind
    let id: UUID
    var identifier: String { "changes:" + kind.rawValue + ":" + id.uuidString }

    init(kind: Kind, id: UUID) {
        self.kind = kind
        self.id = id
    }

    init?(identifier: String) {
        let parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "changes",
              let kind = Kind(rawValue: String(parts[1])), let id = UUID(uuidString: String(parts[2])) else { return nil }
        self.init(kind: kind, id: id)
    }
}

struct MacWorkspaceChangesPage: View {
    let source: WorkspaceChangesSource
    @Environment(WorkspaceStore.self) private var store
    @State private var comparison: Comparison?
    @State private var failure: String?
    @State private var expandedGroups: Set<Int> = []
    @State private var showsFiles = true
    private var ru: Bool { store.language == "ru" }

    private struct Comparison {
        let path: String
        let diff: MacWorkspaceTextDiff
        var fileName: String { (path as NSString).lastPathComponent }
    }

    var body: some View {
        GeometryReader { geometry in
            let canShowFiles = geometry.size.width >= 560 && comparison?.diff.rows.isEmpty == false
            VStack(spacing: 0) {
                toolbar(canShowFiles: canShowFiles)
                Divider()
                if let comparison {
                    ScrollViewReader { scroll in
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                fileHeader(comparison)
                                Divider()
                                diffContent(comparison.diff)
                            }.frame(maxWidth: .infinity)
                            if canShowFiles && showsFiles {
                                Divider()
                                fileList(comparison) { scroll.scrollTo("first-line", anchor: .top) }
                            }
                        }
                    }
                } else if let failure {
                    message(failure, glyph: .warning)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(WorkspaceStyle.canvas)
        .accessibilityIdentifier("workspace.changes.page")
        .task(id: source) { await load() }
    }

    private var scope: String {
        switch source.kind {
        case .draft: ru ? "Правки черновика" : "Draft changes"
        case .creation: ru ? "Файл целиком" : "Full file"
        case .fileWrite: ru ? "Изменение файла" : "File change"
        }
    }

    private func toolbar(canShowFiles: Bool) -> some View {
        HStack(spacing: 10) {
            BlotIcon(.pullRequest, size: BlotIconSize.control).foregroundStyle(WorkspaceStyle.secondary)
            Text(scope).font(.system(size: 13, weight: .medium)).accessibilityAddTraits(.isHeader)
            Spacer()
            if canShowFiles {
                Button { showsFiles.toggle() } label: {
                    BlotIcon(.inspector, size: BlotIconSize.control).frame(width: 30, height: 30)
                        .background(showsFiles ? BlotColor.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(BlotPlainButtonStyle())
                .accessibilityLabel(showsFiles ? (ru ? "Скрыть список файлов" : "Hide file list") : (ru ? "Показать список файлов" : "Show file list"))
            }
        }.padding(.horizontal, 14).frame(height: 42)
    }

    private func fileHeader(_ comparison: Comparison) -> some View {
        HStack(spacing: 10) {
            BlotIcon(.document, size: BlotIconSize.control).foregroundStyle(WorkspaceStyle.secondary)
            Text(comparison.path).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                .help(comparison.path)
            Spacer(minLength: 6)
            counts(comparison.diff)
        }.padding(.horizontal, 14).frame(height: 40)
    }

    private func fileList(_ comparison: Comparison, jumpToFile: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ru ? "Файлы изменений" : "Changed files")
                .font(.caption.weight(.medium)).foregroundStyle(WorkspaceStyle.secondary)
                .accessibilityAddTraits(.isHeader)
            Button(action: jumpToFile) {
                HStack(alignment: .top, spacing: 7) {
                    BlotIcon(.document, size: BlotIconSize.inline)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(comparison.fileName).lineLimit(2).truncationMode(.middle)
                        counts(comparison.diff)
                    }
                    Spacer(minLength: 0)
                }.font(.system(size: 12)).padding(8)
                    .background(BlotColor.selected, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(BlotPlainButtonStyle()).help(comparison.path)
            Spacer(minLength: 0)
        }.padding(12).frame(width: 164, alignment: .leading).background(BlotColor.sidebar)
    }

    @ViewBuilder private func diffContent(_ diff: MacWorkspaceTextDiff) -> some View {
        if diff.rows.isEmpty && diff.hasBaseline {
            message(source.kind == .draft
                    ? (ru ? "Нет несохранённых изменений" : "No unsaved changes")
                    : (ru ? "Нет изменений в строках" : "No line changes"),
                    glyph: .checkCircle)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("first-line").accessibilityHidden(true)
                    if !diff.hasBaseline {
                        note(ru ? "Предыдущая версия недоступна. Показано текущее содержимое." : "The previous version is unavailable. Showing the recorded contents.")
                    } else if diff.approximate {
                        note(ru ? "Для большого файла показан изменённый диапазон." : "Showing the changed range for this large file.")
                    }
                    ForEach(diff.rows) { row in
                        switch row {
                        case .line(let line): lineRow(line)
                        case .unchanged(let lines): unchangedRows(lines, id: row.id)
                        }
                    }
                    if diff.truncated {
                        note(ru ? "Показаны первые 20 000 строк сравнения." : "Showing the first 20,000 lines of the comparison.")
                    }
                }
            }
        }
    }

    @ViewBuilder private func unchangedRows(_ lines: [DiffLine], id: Int) -> some View {
        let expanded = expandedGroups.contains(id)
        Button {
            if expanded { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
        } label: {
            HStack(spacing: 8) {
                BlotIcon(expanded ? .chevronDown : .chevronRight, size: BlotIconSize.inline)
                Text(ru ? "Строк без изменений: \(lines.count)" : "\(lines.count) unchanged lines")
                Spacer(minLength: 0)
            }.font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                .padding(.horizontal, 14).frame(height: 30)
                .background(BlotColor.fill).contentShape(Rectangle())
        }.buttonStyle(BlotPlainButtonStyle())
            .accessibilityValue(expanded ? (ru ? "Развёрнуто" : "Expanded") : (ru ? "Свёрнуто" : "Collapsed"))
        if expanded { ForEach(lines) { lineRow($0) } }
    }

    private func lineRow(_ line: DiffLine) -> some View {
        let tint: Color = switch line.tone {
        case .added: .green
        case .removed: .red
        default: .clear
        }
        return HStack(alignment: .top, spacing: 7) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(line.tone == .added ? "+" : line.tone == .removed ? "−" : " ")
                .foregroundStyle(tint).frame(width: 10)
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, design: .monospaced)).padding(.horizontal, 10).padding(.vertical, 4)
        .background(tint.opacity(0.11))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2).accessibilityHidden(true) }
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map { String($0) } ?? "")
            .foregroundStyle(WorkspaceStyle.secondary).frame(width: 34, alignment: .trailing)
    }

    @ViewBuilder private func counts(_ diff: MacWorkspaceTextDiff) -> some View {
        if diff.hasBaseline {
            HStack(spacing: 6) {
                Text("+\(diff.added)").foregroundStyle(.green)
                Text("−\(diff.removed)").foregroundStyle(.red)
            }.font(.system(size: 12, design: .monospaced)).fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ru ? "Добавлено строк: \(diff.added), удалено: \(diff.removed)" : "\(diff.added) lines added, \(diff.removed) removed")
        }
    }

    private func message(_ title: String, glyph: BlotGlyph) -> some View {
        VStack(spacing: 10) {
            BlotIcon(glyph, size: 28)
            Text(title).font(.callout).multilineTextAlignment(.center)
        }.foregroundStyle(WorkspaceStyle.secondary).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(WorkspaceStyle.secondary).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background(BlotColor.fill)
    }

    private func load() async {
        do {
            let input = try await comparisonInput()
            let diff = await _Concurrency.Task.detached(priority: .userInitiated) {
                MacWorkspaceTextDiff(before: input.before, after: input.after)
            }.value
            try _Concurrency.Task.checkCancellation()
            comparison = .init(path: input.path, diff: diff)
        } catch is CancellationError {
            return
        } catch {
            failure = ru ? "Не удалось загрузить изменения файла." : "Could not load file changes."
        }
    }

    private func comparisonInput() async throws -> (path: String, before: String?, after: String) {
        if source.kind == .fileWrite {
            guard let change = try await store.fileCommands?.workspaceFileChange(source.id) else {
                throw WorkspaceServiceError.unavailable
            }
            return (change.path, change.created ? "" : change.before, change.after)
        }
        let session = store.documentEdits[source.id]
        let saved: WorkspaceEditableDocument?
        if let session { saved = session.saved }
        else { saved = try await store.fileCommands?.editableWorkspaceDocument(source.id) }
        guard let saved else { throw WorkspaceServiceError.unavailable }
        let path = store.snapshot.artifacts.first { $0.metadata.id == source.id }?.name ?? saved.title + "." + saved.fileExtension
        let before = source.kind == .draft ? try WorkspaceReportSource.comparisonText(saved) : ""
        let after = try WorkspaceReportSource.comparisonText(source.kind == .draft ? session?.draft ?? saved : saved)
        return (path, before, after)
    }
}
