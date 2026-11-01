import BlotDesign
import AppKit
import Observation

nonisolated struct LibraryImage: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let bookmark: Data

    func load() throws -> NSImage {
        guard let image = NSImage(data: try previewData()) else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    nonisolated func previewData() throws -> Data {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                          bookmarkDataIsStale: &stale)
        return try LocalPreviewReader.read(url)
    }
}

nonisolated struct SavedSite: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var url: URL
}

nonisolated struct AssistantProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var instructions: String
}

@Observable
final class WorkspaceLibrary {
    nonisolated private struct Library: Codable, Sendable {
        var images: [LibraryImage] = []
        var sites: [SavedSite] = []
        var assistants: [AssistantProfile] = []
        var profileDetails: ProfileDetails?
        var featuredSiteIDs: Set<UUID>?
    }

    private var library = Library()
    private var account: String?
    private var revision = 0
    private let defaults: UserDefaults
    var images: [LibraryImage] { library.images }
    var sites: [SavedSite] { library.sites }
    var assistants: [AssistantProfile] { library.assistants }
    var profileDetails: ProfileDetails? { library.profileDetails }
    var featuredSiteIDs: Set<UUID> { library.featuredSiteIDs ?? [] }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func selectAccount(_ email: String?) {
        revision += 1
        let email = email?.lowercased()
        guard account != email else { return }
        account = email
        library = email.flatMap { defaults.data(forKey: key($0)) }
            .flatMap { try? JSONDecoder().decode(Library.self, from: $0) } ?? Library()
    }

    func restoreAccount(_ email: String?) async {
        let email = email?.lowercased()
        guard account != email else { return }
        revision += 1
        let version = revision
        let data = email.flatMap { defaults.data(forKey: key($0)) }
        let restored = await Task.detached(priority: .userInitiated) { Self.decode(data) }.value
        guard !Task.isCancelled, revision == version else { return }
        account = email
        library = restored
    }

    nonisolated private static func decode(_ data: Data?) -> Library {
        data.flatMap { try? JSONDecoder().decode(Library.self, from: $0) } ?? Library()
    }

    func importImages(_ urls: [URL]) throws {
        var imported: [LibraryImage] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard NSImage(contentsOf: url) != nil else { throw CocoaError(.fileReadCorruptFile) }
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            imported.append(LibraryImage(id: UUID(), name: url.lastPathComponent, bookmark: bookmark))
        }
        library.images.insert(contentsOf: imported, at: 0)
        persist()
    }

    func saveSite(_ site: SavedSite) { library.sites.insert(site, at: 0); persist() }
    func saveAssistant(_ assistant: AssistantProfile) {
        if let index = library.assistants.firstIndex(where: { $0.id == assistant.id }) {
            library.assistants[index] = assistant
        } else { library.assistants.insert(assistant, at: 0) }
        persist()
    }
    func removeImage(_ id: UUID) { library.images.removeAll { $0.id == id }; persist() }
    func removeSite(_ id: UUID) {
        library.sites.removeAll { $0.id == id }
        library.featuredSiteIDs?.remove(id)
        persist()
    }
    func removeAssistant(_ id: UUID) { library.assistants.removeAll { $0.id == id }; persist() }
    func saveProfile(_ details: ProfileDetails) {
        guard details.isValid else { return }
        library.profileDetails = details
        persist()
    }
    func featureSites(_ ids: Set<UUID>) {
        library.featuredSiteIDs = ids.intersection(Set(library.sites.map(\.id)))
        persist()
    }
    private func key(_ account: String) -> String { "blot.workspace.library." + account }
    private func persist() {
        guard let account, let data = try? JSONEncoder().encode(library) else { return }
        defaults.set(data, forKey: key(account))
    }
}
