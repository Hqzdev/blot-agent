import BlotDesign
import PDFKit
import SwiftUI

/// Document content stays inside the workspace panel, with the app's own surrounding controls.
struct WorkspacePDFPreview: View {
    let url: URL
    @Environment(WorkspaceStore.self) private var store
    @State private var document: PDFDocument?
    @State private var loadedURL: URL?
    @State private var page = 1
    @State private var request: PDFPageRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loadedURL != url {
                ProgressView()
            } else if let document, document.pageCount > 0 {
                WorkspaceCounter(title: store.language == "ru" ? "Страница" : "Page",
                    value: Binding(get: { page }, set: { page = $0; request = PDFPageRequest(page: $0) }), range: 1...document.pageCount)
                PDFContent(document: document, request: request) { page = $0 }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                Text(store.t("File is unavailable")).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: url) {
            guard loadedURL != url else { return }
            document = PDFDocument(url: url)
            page = 1
            request = nil
            loadedURL = url
        }
    }
}

#if os(macOS)
private struct PDFContent: NSViewRepresentable {
    let document: PDFDocument
    let request: PDFPageRequest?
    let pageChanged: (Int) -> Void
    func makeCoordinator() -> PDFNavigation { PDFNavigation(pageChanged: pageChanged) }
    func makeNSView(context: Context) -> PDFView { context.coordinator.makeView() }
    func updateNSView(_ view: PDFView, context: Context) { context.coordinator.update(view, document: document, request: request) }
}
#else
private struct PDFContent: UIViewRepresentable {
    let document: PDFDocument
    let request: PDFPageRequest?
    let pageChanged: (Int) -> Void
    func makeCoordinator() -> PDFNavigation { PDFNavigation(pageChanged: pageChanged) }
    func makeUIView(context: Context) -> PDFView { context.coordinator.makeView() }
    func updateUIView(_ view: PDFView, context: Context) { context.coordinator.update(view, document: document, request: request) }
}
#endif

private struct PDFPageRequest {
    let id = UUID()
    let page: Int
}

@MainActor
private final class PDFNavigation: NSObject {
    private let pageChanged: (Int) -> Void
    private var lastRequest: UUID?

    init(pageChanged: @escaping (Int) -> Void) {
        self.pageChanged = pageChanged
    }

    func makeView() -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.backgroundColor = .clear
        NotificationCenter.default.addObserver(self, selector: #selector(currentPageChanged(_:)), name: .PDFViewPageChanged, object: view)
        return view
    }

    func update(_ view: PDFView, document: PDFDocument, request: PDFPageRequest?) {
        if view.document !== document {
            view.document = document
            lastRequest = nil
        }
        // SwiftUI updates also arrive during native scrolling and resizing.
        guard let request, lastRequest != request.id else { return }
        lastRequest = request.id
        if let target = document.page(at: request.page - 1), view.currentPage != target { view.go(to: target) }
    }

    @objc private func currentPageChanged(_ notification: Notification) {
        guard let view = notification.object as? PDFView else { return }
        // PDFKit may post synchronously while SwiftUI is updating the native view.
        _Concurrency.Task { @MainActor [weak self, weak view] in
            guard let view, let document = view.document, let page = view.currentPage else { return }
            let index = document.index(for: page)
            if (0..<document.pageCount).contains(index) { self?.pageChanged(index + 1) }
        }
    }
}

struct WorkspaceTablePreview: View {
    let rows: [[String]]
    @Environment(WorkspaceStore.self) private var store
    private var visibleRows: Int { min(rows.count, min(200, max(1, 2000 / max(1, columns)))) }
    private var columns: Int { rows.map(\.count).max() ?? 0 }
    var body: some View {
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(0..<visibleRows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(0..<columns, id: \.self) { column in
                            Text(column < rows[row].count ? rows[row][column] : "")
                                .font(row == 0 ? .body.weight(.semibold) : .body).textSelection(.enabled)
                                .frame(width: 160, alignment: .leading).padding(12)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .background(WorkspaceStyle.ink.opacity(row == 0 ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                }
                if visibleRows < rows.count {
                    Text(store.language == "ru" ? "Показано строк: \(visibleRows) из \(rows.count). Полная таблица сохранена в файле." : "Showing \(visibleRows) of \(rows.count) rows. The file contains the full table.")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                }
            }
        }.accessibilityLabel("Table preview")
    }
}
