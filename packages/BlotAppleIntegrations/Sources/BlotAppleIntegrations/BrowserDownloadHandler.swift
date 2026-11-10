import BlotWorkspace
import Foundation
import WebKit
#if os(macOS)
import AppKit
#endif

@MainActor
final class BrowserDownloadHandler: NSObject, WKDownloadDelegate {
    private weak var owner: WorkspaceBrowserController?
    init(owner: WorkspaceBrowserController) { self.owner = owner }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        guard let owner, let item = owner.downloads.first(where: { $0.download === download }), !owner.stopped else { completionHandler(nil); return }
        let safe = String(suggestedFilename.filter { $0 != "/" && $0 != "\\" && !$0.isNewline }.prefix(180))
        item.name = safe.isEmpty || safe == "." || safe == ".." ? "download" : safe
        if let choose = owner.chooseDownload {
            Task {
                guard let url = await choose(item.name), url.isFileURL, !owner.stopped else { item.state = "canceled"; completionHandler(nil); return }
                item.url = url; completionHandler(url)
            }
            return
        }
        #if os(macOS)
        let panel = NSSavePanel(); panel.nameFieldStringValue = item.name
        guard let window = download.webView?.window else { item.state = "canceled"; completionHandler(nil); return }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url, !owner.stopped else { item.state = "canceled"; completionHandler(nil); return }
            item.url = url; completionHandler(url)
        }
        #else
        do {
            let directory = owner.downloadsDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(item.name); item.url = url; completionHandler(url)
        } catch { item.state = "failed"; item.error = "Не удалось сохранить загрузку."; completionHandler(nil) }
        #endif
    }
    func downloadDidFinish(_ download: WKDownload) { owner?.downloads.first { $0.download === download }?.state = "completed" }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = owner?.downloads.first(where: { $0.download === download }) else { return }
        if item.state != "canceled" { item.state = "failed"; item.error = "Загрузка не завершена. Автоматического повтора нет." }
    }
}
