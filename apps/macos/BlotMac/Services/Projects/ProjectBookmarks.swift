import BlotDesign
import Foundation

/// Постоянные bookmarks создаёт только выбор папки пользователем на Mac.
@MainActor
final class ProjectBookmarks {
    static let shared = ProjectBookmarks()
    private var active: [String: URL] = [:]
    private let key = "blot.project.bookmarks"

    func remember(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        var bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        bookmarks[path] = data
        UserDefaults.standard.set(bookmarks, forKey: key)
        return path
    }

    func transfer(_ path: String) throws -> String {
        let url: URL
        if let existing = active[path] { url = existing }
        else {
            guard let data = (UserDefaults.standard.dictionary(forKey: key) as? [String: Data])?[path] else { throw CocoaError(.fileReadNoPermission) }
            var stale = false
            url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            guard !stale, url.resolvingSymlinksInPath().standardizedFileURL.path == path,
                  url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
            active[path] = url
        }
        // Передаваемый процессу bookmark содержит implicit scope, а не привязку к ID приложения.
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString()
    }

    func close() { for url in active.values { url.stopAccessingSecurityScopedResource() }; active.removeAll() }
}
