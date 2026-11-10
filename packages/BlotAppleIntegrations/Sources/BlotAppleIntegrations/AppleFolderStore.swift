import BlotWorkspace
import Foundation
import Darwin

/// Bookmarks stay in this device/account's container and never enter replicated Connection records.
@MainActor
final class AppleFolderStore {
    private struct Entry: Codable { let resource: AppleResource; let bookmark: Data }
    private let file: URL
    private var entries: [Entry]
    init(file: URL) throws {
        self.file = file
        entries = FileManager.default.fileExists(atPath: file.path) ? try PropertyListDecoder().decode([Entry].self, from: Data(contentsOf: file)) : []
    }
    var resources: [AppleResource] { entries.map(\.resource) }
    func add(_ url: URL) throws -> AppleResource {
        guard url.startAccessingSecurityScopedResource() else { throw AppleIntegrationError.permissionDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw AppleIntegrationError.invalidArguments }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        let resource = AppleResource(id: UUID().uuidString, name: url.lastPathComponent)
        let entry = Entry(resource: resource, bookmark: try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil))
        let updated = entries + [entry]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListEncoder().encode(updated).write(to: file, options: .atomic)
        entries = updated
        return resource
    }
    func accessible(_ ids: [String]) -> Bool {
        !ids.isEmpty && ids.allSatisfy { id in
            guard let root = try? resolve(id), root.startAccessingSecurityScopedResource() else { return false }
            root.stopAccessingSecurityScopedResource(); return true
        }
    }
    func preview(_ a: AppleArguments) throws -> ChatJSON {
        let root = try resolve(a.required("resource_id"))
        guard root.startAccessingSecurityScopedResource() else { throw AppleIntegrationError.permissionDenied }
        defer { root.stopAccessingSecurityScopedResource() }
        let target = try Self.containedURL(root: root, path: a.required("path"))
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        return appleObject(["path": a["path"] ?? "", "name": target.lastPathComponent,
            "size": String(describing: attributes[.size] ?? ""), "modified": String(describing: attributes[.modificationDate] ?? "")])
    }
    func execute(_ tool: AppleTool, arguments a: AppleArguments) throws -> ChatJSON {
        let root = try resolve(a.required("resource_id"))
        guard root.startAccessingSecurityScopedResource() else { throw AppleIntegrationError.permissionDenied }
        defer { root.stopAccessingSecurityScopedResource() }
        let url = try Self.containedURL(root: root, path: a["path"] ?? "")
        if tool.writes && url.resolvingSymlinksInPath() == root.resolvingSymlinksInPath() { throw AppleIntegrationError.permissionDenied }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<ChatJSON, Error> = .failure(AppleIntegrationError.uncertainResult)
        let operation: (URL) -> Void = { coordinated in
            result = Result { try self.perform(tool.operation, at: coordinated, root: root, arguments: a) }
        }
        if tool.writes {
            coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError, byAccessor: operation)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError, byAccessor: operation)
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
    static func containedURL(root: URL, path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw AppleIntegrationError.permissionDenied }
        guard let rootPointer = realpath(root.path, nil) else { throw AppleIntegrationError.permissionDenied }
        let canonicalRoot = URL(fileURLWithPath: String(cString: rootPointer)); free(rootPointer)
        var target = canonicalRoot
        for component in path.split(separator: "/") where component != "." {
            target.appendPathComponent(String(component))
            if let pointer = realpath(target.path, nil) {
                target = URL(fileURLWithPath: String(cString: pointer)); free(pointer)
            } else {
                guard errno == ENOENT else { throw AppleIntegrationError.permissionDenied }
                if (try? FileManager.default.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType) == .typeSymbolicLink { throw AppleIntegrationError.permissionDenied }
            }
            guard target == canonicalRoot || target.path.hasPrefix(canonicalRoot.path + "/") else { throw AppleIntegrationError.permissionDenied }
        }
        return target
    }

    private func perform(_ operation: String, at url: URL, root: URL, arguments a: AppleArguments) throws -> ChatJSON {
        _ = try Self.containedURL(root: root, path: a["path"] ?? "")
        let manager = FileManager.default
        switch operation {
        case "list":
            return .array(try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(100).map {
                    appleObject(["name": $0.lastPathComponent, "path": ((a["path"] ?? "") as NSString).appendingPathComponent($0.lastPathComponent),
                                 "directory": String((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)])
                })
        case "search":
            let query = try a.required("query")
            guard let iterator = manager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw AppleIntegrationError.missingResource }
            let base = try Self.containedURL(root: root, path: "")
            var matches: [ChatJSON] = [], inspected = 0
            while let item = iterator.nextObject() as? URL {
                try _Concurrency.Task.checkCancellation()
                inspected += 1
                guard inspected <= 10000, matches.count < 100 else { return .object(["matches": .array(matches), "truncated": .bool(true)]) }
                let relative = String(item.path.dropFirst(base.path.count + 1))
                guard (try? Self.containedURL(root: base, path: relative)) != nil else { iterator.skipDescendants(); continue }
                if item.lastPathComponent.localizedCaseInsensitiveContains(query) {
                    matches.append(appleObject(["name": item.lastPathComponent, "path": relative,
                        "directory": String((try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)]))
                }
            }
            return .object(["matches": .array(matches), "truncated": .bool(false)])
        case "read":
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 48 * 1024 else { throw AppleIntegrationError.invalidArguments }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 48 * 1024, let content = String(data: data, encoding: .utf8) else { throw AppleIntegrationError.invalidArguments }
            return appleObject(["content": content])
        case "create", "update":
            let exists = manager.fileExists(atPath: url.path)
            guard operation == "create" ? !exists : exists else { throw AppleIntegrationError.invalidArguments }
            guard let content = a["content"] else { throw AppleIntegrationError.invalidArguments }
            let data = Data(content.utf8)
            try data.write(to: url, options: operation == "create" ? [.withoutOverwriting] : [.atomic])
        case "move":
            let destination = try Self.containedURL(root: root, path: a.required("destination"))
            guard destination != root.resolvingSymlinksInPath() else { throw AppleIntegrationError.permissionDenied }
            try manager.moveItem(at: url, to: destination)
        case "delete":
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
               !(try manager.contentsOfDirectory(atPath: url.path)).isEmpty { throw AppleIntegrationError.invalidArguments }
            try manager.removeItem(at: url)
        default: throw AppleIntegrationError.unavailable
        }
        return appleObject(["state": "succeeded", "path": a["path"] ?? ""])
    }
    private func resolve(_ id: String) throws -> URL {
        guard let entry = entries.first(where: { $0.resource.id == id }) else { throw AppleIntegrationError.missingResource }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: entry.bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw AppleIntegrationError.permissionDenied }
        return url
    }
}
