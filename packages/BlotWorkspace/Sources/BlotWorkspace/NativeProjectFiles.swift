#if os(macOS)
import CryptoKit
import Foundation

/// Scoped file operations are separate from the explicitly trusted, unrestricted command runner.
public struct NativeProjectFiles: Sendable {
    private let root: URL
    public init(root: String) throws {
        let url = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard root.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { throw NativeExecutionError.accessDenied }
        self.root = url
    }
    func url(_ path: String, directory: Bool = false) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4096 else { throw NativeExecutionError.accessDenied }
        let candidate = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate == root && directory || candidate.path.hasPrefix(root.path + "/"),
              !candidate.pathComponents.dropFirst(root.pathComponents.count).contains(".git") else { throw NativeExecutionError.accessDenied }
        if directory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw NativeExecutionError.invalidRequest }
        }
        return candidate
    }
    public func read(_ path: String) throws -> ChatJSON {
        let target = try url(path)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else { throw NativeExecutionError.invalidRequest }
        let data = try Data(contentsOf: target)
        guard String(data: data, encoding: .utf8) != nil else { throw NativeExecutionError.invalidRequest }
        return .object(["path": .string(path), "content": .string(String(decoding: data.prefix(48_000), as: UTF8.self)), "sha256": .string(Self.hash(data)), "truncated": .bool(data.count > 48_000)])
    }
    public func write(_ path: String, content: String, expectedHash: String) throws -> ChatJSON {
        let target = try url(path)
        guard content.utf8.count <= 48 * 1024 else { throw NativeExecutionError.invalidRequest }
        var coordinationError: NSError?, failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { coordinated in
            do {
                let old: Data?
                var permissions: NSNumber?
                if FileManager.default.fileExists(atPath: coordinated.path) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: coordinated.path)
                    let size = (attributes[.size] as? NSNumber)?.intValue ?? Int.max
                    permissions = attributes[.posixPermissions] as? NSNumber
                    guard size <= 1_048_576 else { throw NativeExecutionError.invalidRequest }
                    old = try Data(contentsOf: coordinated)
                } else { old = nil }
                guard (old.map(Self.hash) ?? "missing") == expectedHash, try url(path) == target else { throw NativeExecutionError.changed }
                try Data(content.utf8).write(to: coordinated, options: .atomic)
                if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: coordinated.path) }
            } catch { failure = error }
        }
        if let coordinationError { throw coordinationError }; if let failure { throw failure }
        return .object(["path": .string(path), "sha256": .string(Self.hash(Data(content.utf8))), "state": .string("succeeded")])
    }
    public func search(_ query: String) throws -> ChatJSON {
        guard !query.isEmpty, query.utf8.count <= 1000 else { throw NativeExecutionError.invalidRequest }
        let excluded: Set<String> = [".git", ".build", "node_modules", ".gradle", "DerivedData"]
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { throw NativeExecutionError.unavailable }
        var results: [ChatJSON] = [], inspected = 0
        for case let file as URL in iterator {
            inspected += 1
            if inspected > 10_000 || results.count >= 100 { break }
            if excluded.contains(file.lastPathComponent) { iterator.skipDescendants(); continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 256 * 1024,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            for (line, value) in text.components(separatedBy: .newlines).enumerated() where value.contains(query) {
                results.append(.object(["path": .string(relative), "line": .number(Double(line + 1)), "text": .string(String(value.prefix(500)))]))
                if results.count >= 100 { break }
            }
        }
        return .object(["matches": .array(results), "truncated": .bool(inspected > 10_000 || results.count >= 100)])
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
