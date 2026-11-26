import Foundation

/// Stable document links address an artifact ID, never an arbitrary local filesystem path.
public enum WorkspaceResultLink {
    public static func url(for artifactID: UUID) -> URL { URL(string: "blot-file://" + artifactID.uuidString)! }
    public static func artifactID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "blot-file", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/", let host = url.host else { return nil }
        return UUID(uuidString: host)
    }
    public struct Website: Identifiable, Equatable, Sendable {
        public let url: URL
        public let title: String
        public var id: String { url.absoluteString }
    }
    public static func websites(in markdown: String) -> [Website] {
        guard markdown.utf8.count <= 262_144, let text = try? AttributedString(markdown: markdown) else { return [] }
        var result: [Website] = [], seen = Set<URL>()
        for run in text.runs {
            guard let url = run.link, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.user == nil, url.password == nil, url.host != nil, seen.insert(url).inserted else { continue }
            let title = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(.init(url: url, title: title.isEmpty ? url.host! : title))
            if result.count == 3 { break }
        }
        return result
    }
}
