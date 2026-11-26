import BlotDesign
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspacePageProviding { func pageService() async throws -> WorkspacePageService }
extension LocalWorkspaceService: WorkspacePageProviding {
    func pageService() async throws -> WorkspacePageService {
        if let pages { return pages }
        let identity = try await context(), files = try await fileService()
        if let pages { return pages }
        let service = WorkspacePageService(repository: repository, identity: identity, files: files)
        pages = service; return service
    }
    func pageTools() async throws -> WorkspacePageTools {
        .init(service: try await pageService(), repository: repository, identity: try await context())
    }
}
extension WorkspaceAccountApplicationService: WorkspacePageProviding {
    func pageService() async throws -> WorkspacePageService {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        return try await local.pageService()
    }
}

struct WorkspacePagesButton: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    var body: some View {
        Button {
            if let panelNavigation { panelNavigation.open(.pages) }
            else { store.navigate(.pages) }
        } label: {
            Label {
                Text(store.language == "ru" ? "Библиотека" : "Library")
            } icon: {
                BlotIcon(.document)
            }
        }
    }
}

struct WorkspacePagesView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var documents: [WorkspacePageSummary] = []
    @State private var query = ""
    @State private var filter = "all"
    @State private var selected: WorkspacePageDocument?
    @State private var editing = false
    @State private var failure: String?
    @State private var working = false
    @State private var exportURL: URL?
    @State private var history: WorkspacePageDocument?
    private var ru: Bool { store.language == "ru" }
    private var visible: [WorkspacePageSummary] {
        documents.filter { $0.document.archived == (filter == "archived") && (filter != "pinned" || $0.document.pinned) && (query.isEmpty || $0.document.title.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let selected {
                        HStack {
                            Button(ru ? "Все страницы" : "All pages") { self.selected = nil; exportURL = nil }
                            Spacer()
                            Button(store.t("Edit")) { editing = true }
                            Button(ru ? "История" : "History") { history = selected }
                            Button(selected.pinned ? (ru ? "Открепить" : "Unpin") : (ru ? "Закрепить" : "Pin")) { changeFlags(selected, pinned: !selected.pinned) }
                            Button(selected.archived ? (ru ? "Восстановить" : "Restore") : (ru ? "В архив" : "Archive")) { changeFlags(selected, archived: !selected.archived) }
                        }.disabled(working)
                        Text(selected.title).font(.largeTitle)
                        TextField(ru ? "Фильтр строк таблиц" : "Filter table rows", text: $query)
                        ForEach(selected.blocks) { block in render(block) }
                        if let data = try? JSONEncoder().encode(selected) { WorkspacePublishButton(kind: "page", title: selected.title, data: data) }
                        if let exportURL { ShareLink(item: exportURL) { Text(ru ? "Экспорт файла" : "Export file") } }
                    } else {
                        HStack {
                            TextField(store.t("Search"), text: $query)
                            WorkspacePublicationsButton()
                            Button(ru ? "Новая страница" : "New page") { editing = true }
                        }
                        WorkspaceChoice(title: ru ? "Показать" : "Show", selection: $filter, options: [.init("all", ru ? "Все" : "All"), .init("pinned", ru ? "Закреплённые" : "Pinned"), .init("archived", ru ? "Архив" : "Archive")])
                        ForEach(visible) { summary in
                            Button {
                                guard !summary.conflicting else { history = summary.document; return }
                                selected = summary.document; query = ""
                                _Concurrency.Task { exportURL = try? await store.pageCommands?.pageService().export(summary.document) }
                            } label: {
                                HStack {
                                    BlotIcon(symbol: summary.document.pinned ? "pin.fill" : "doc.richtext")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(summary.document.title).font(.headline)
                                        Text(summary.document.updatedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(); BlotIcon(symbol: "chevron.right")
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if visible.isEmpty { Text(ru ? "Здесь появятся созданные страницы и отчёты." : "Created pages and reports appear here.").foregroundStyle(.secondary) }
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }.padding(20)
            }
            .navigationTitle(selected == nil ? "Library" : selected!.title)
        }
        .task { await reload() }
        .task(id: store.selectedPageID) {
            if let id = store.selectedPageID { await reload(); selected = documents.first { $0.id == id }?.document }
        }
        .workspacePanelSheet(isPresented: $editing) {
            WorkspacePageEditor(document: selected) { saved in selected = saved; await reload() }.environment(store)
        }
        .workspacePanelSheet(item: $history) { page in
            WorkspacePageHistory(pageID: page.id) { saved in selected = saved; await reload() }.environment(store)
        }
    }
    @ViewBuilder private func render(_ block: WorkspacePageDocument.Block) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !block.title.isEmpty { Text(block.title).font(.headline) }
            switch block.kind {
            case .text: Text(block.text).textSelection(.enabled)
            case .metric: Text(block.text).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
            case .link:
                if let url = URL(string: block.text) { Link(block.text, destination: url) }
            case .table:
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        GridRow { ForEach(Array(block.columns.enumerated()), id: \.offset) { _, column in Text(column).fontWeight(.semibold) } }
                        ForEach(Array(block.rows.enumerated()).filter { query.isEmpty || $0.element.joined(separator: " ").localizedCaseInsensitiveContains(query) }, id: \.offset) { _, row in
                            GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(cell).textSelection(.enabled) } }
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func reload() async {
        do { documents = try await store.pageCommands?.pageService().list() ?? []; failure = nil }
        catch { failure = WorkspaceFailureCopy.message(error) }
    }
    private func changeFlags(_ page: WorkspacePageDocument, pinned: Bool? = nil, archived: Bool? = nil) {
        guard let commands = store.pageCommands, !working else { return }; working = true
        _Concurrency.Task {
            defer { working = false }
            do {
                selected = try await commands.pageService().save(id: page.id, expectedRevision: page.revisionID, title: page.title,
                    blocks: page.blocks, pinned: pinned ?? page.pinned, archived: archived ?? page.archived)
                if archived == true { selected = nil }
                await reload(); try await store.refreshContent()
            } catch { failure = WorkspaceFailureCopy.message(error) }
        }
    }
}

private struct WorkspacePageEditor: View {
    let document: WorkspacePageDocument?
    let saved: @MainActor (WorkspacePageDocument) async -> Void
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var title = ""
    @State private var blocks: [WorkspacePageDocument.Block] = []
    @State private var working = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                TextField(store.t("Name"), text: $title)
                ForEach(blocks.indices, id: \.self) { index in
                    TextField(store.language == "ru" ? "Заголовок блока" : "Block title", text: $blocks[index].title)
                    if blocks[index].kind != .table { TextField(store.language == "ru" ? "Содержимое" : "Content", text: $blocks[index].text, axis: .vertical).lineLimit(3...15) }
                    else { Text(store.language == "ru" ? "Таблицу можно обновить через агента." : "Ask your agent to update the table.").font(.caption).foregroundStyle(.secondary) }
                }
                Button(store.language == "ru" ? "Добавить текстовый блок" : "Add text block") { blocks.append(.init(text: "")) }
                if let failure { Text(failure).foregroundStyle(.red) }
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: document == nil ? (store.language == "ru" ? "Новая страница" : "New page") : store.t("Edit")) {
                    Button(store.t("Cancel")) { dismiss() }.disabled(working)
                    Button(store.t("Save")) {
                        guard !working, let commands = store.pageCommands else { return }; working = true
                        _Concurrency.Task {
                            defer { working = false }
                            do {
                                let page = try await commands.pageService().save(id: document?.id ?? UUID(), expectedRevision: document?.revisionID,
                                    title: title, blocks: blocks, pinned: document?.pinned ?? false, archived: document?.archived ?? false)
                                await saved(page); try await store.refreshContent(); dismiss()
                            } catch { failure = WorkspaceFailureCopy.message(error) }
                        }
                    }.buttonStyle(WorkspaceButtonStyle(.primary)).disabled(working || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.workspaceEditorChrome()
        }
        .onAppear { title = document?.title ?? ""; blocks = document?.blocks ?? [.init(text: "")] }
        .interactiveDismissDisabled(working)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 480)
        #endif
    }
}

private struct WorkspacePageHistory: View {
    let pageID: UUID
    let restored: @MainActor (WorkspacePageDocument) async -> Void
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var revisions: [WorkspacePageDocument] = []
    @State private var working = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var heads: Set<UUID> {
        let parents = Set(revisions.flatMap(\.parents))
        return Set(revisions.filter { !parents.contains($0.revisionID) }.map(\.revisionID))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if heads.count > 1 {
                        Text(ru ? "Есть изменения с нескольких устройств. Выберите версию для восстановления. Остальные версии останутся в истории." : "Several devices changed this page. Choose a revision to restore. Other revisions remain in history.")
                    }
                    ForEach(revisions, id: \.revisionID) { revision in
                        WorkspaceCard {
                            Text(revision.title).font(.headline)
                            Text(revision.updatedAt, format: .dateTime.day().month().year().hour().minute().second()).font(.caption)
                            Text(revision.blocks.map(\.text).joined(separator: "\n")).lineLimit(6).textSelection(.enabled)
                            if heads == [revision.revisionID], !revision.archived { Text(ru ? "Текущая версия" : "Current revision").foregroundStyle(.secondary) }
                            else { Button(ru ? "Восстановить эту версию" : "Restore this revision") { restore(revision) }.disabled(working) }
                        }
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }.padding(20)
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "История страницы" : "Page history") {
                    Button(store.t("Close")) { dismiss() }.disabled(working)
                }
            }.workspaceEditorChrome()
        }
        .task {
            do { revisions = try await store.pageCommands?.pageService().revisions(pageID) ?? [] }
            catch { failure = WorkspaceFailureCopy.message(error) }
        }
        .interactiveDismissDisabled(working)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 480)
        #endif
    }
    private func restore(_ revision: WorkspacePageDocument) {
        guard !working, let commands = store.pageCommands else { return }; working = true
        let expected = heads
        _Concurrency.Task {
            defer { working = false }
            do {
                let page = try await commands.pageService().restore(pageID: pageID, revisionID: revision.revisionID, expectedHeads: expected)
                await restored(page); try await store.refreshContent(); dismiss()
            } catch { failure = WorkspaceFailureCopy.message(error) }
        }
    }
}
