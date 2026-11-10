#if os(macOS)
import CryptoKit
import Darwin
import Foundation

/// Directory descriptors keep structured file tools inside their root, including across symlink changes.
struct NativeScopedFiles {
    private let descriptor: Int32
    init(root: URL) throws {
        guard root.standardizedFileURL.path == root.standardizedFileURL.resolvingSymlinksInPath().path else { throw NativeExecutionError.accessDenied }
        descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw NativeExecutionError.accessDenied }
    }
    func closeRoot() { close(descriptor) }
    private func components(_ path: String) throws -> [String] {
        guard !path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4096 else { throw NativeExecutionError.accessDenied }
        let parts = path.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !parts.contains(".."), !parts.contains(".git") else { throw NativeExecutionError.accessDenied }
        return parts
    }
    private func directory(_ parts: [String], create: Bool) throws -> Int32 {
        var current = dup(descriptor)
        guard current >= 0 else { throw NativeExecutionError.unavailable }
        do {
            for part in parts {
                if create, mkdirat(current, part, 0o700) != 0, errno != EEXIST { throw NativeExecutionError.accessDenied }
                let next = openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw NativeExecutionError.accessDenied }
                close(current); current = next
            }
            return current
        } catch { close(current); throw error }
    }
    func mkdir(_ path: String) throws {
        let parts = try components(path)
        guard !parts.isEmpty else { throw NativeExecutionError.invalidRequest }
        close(try directory(parts, create: true))
    }
    func list(_ path: String) throws -> ChatJSON {
        let fd = try directory(components(path), create: false)
        guard let stream = fdopendir(fd) else { close(fd); throw NativeExecutionError.accessDenied }
        defer { closedir(stream) }
        var items: [ChatJSON] = [], inspected = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." || name == ".git" { continue }
            inspected += 1
            guard inspected <= 200 else { break }
            var attributes = stat()
            guard fstatat(fd, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            items.append(.object(["name": .string(name), "directory": .bool((attributes.st_mode & S_IFMT) == S_IFDIR),
                                  "symbolic_link": .bool((attributes.st_mode & S_IFMT) == S_IFLNK)]))
        }
        return .object(["entries": .array(items), "truncated": .bool(inspected > 200)])
    }
    func read(_ path: String, maximum: Int = 1_048_576) throws -> Data {
        let parts = try components(path)
        guard let name = parts.last else { throw NativeExecutionError.invalidRequest }
        let parent = try directory(Array(parts.dropLast()), create: false); defer { close(parent) }
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw NativeExecutionError.accessDenied }; defer { close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, (attributes.st_mode & S_IFMT) == S_IFREG,
              attributes.st_size >= 0, attributes.st_size <= maximum else { throw NativeExecutionError.invalidRequest }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw NativeExecutionError.invalidRequest }; return data
    }
    func write(_ path: String, data: Data, expected: String, maximum: Int = 48 * 1024) throws -> String {
        guard data.count <= maximum else { throw NativeExecutionError.invalidRequest }
        let parts = try components(path)
        guard let name = parts.last else { throw NativeExecutionError.invalidRequest }
        let parent = try directory(Array(parts.dropLast()), create: false); defer { close(parent) }
        var attributes = stat()
        let exists = fstatat(parent, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0
        guard !exists || (attributes.st_mode & S_IFMT) == S_IFREG else { throw NativeExecutionError.accessDenied }
        let previous = exists ? try read(path, maximum: max(maximum, 1_048_576)) : nil
        guard expected == "managed" || (previous.map(Self.hash) ?? "missing") == expected else { throw NativeExecutionError.changed }
        let temporary = ".blot-write-" + UUID().uuidString
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw NativeExecutionError.accessDenied }
        defer { close(fd); unlinkat(parent, temporary, 0) }
        if exists { guard fchmod(fd, attributes.st_mode & 0o777) == 0 else { throw NativeExecutionError.accessDenied } }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(fd) == 0 else { throw NativeExecutionError.unavailable }
        if exists {
            guard let current = try? read(path, maximum: max(maximum, 1_048_576)), current == previous else { throw NativeExecutionError.changed }
        }
        let flags: UInt32 = expected == "missing" ? UInt32(RENAME_EXCL) : 0
        guard renameatx_np(parent, temporary, parent, name, flags) == 0 else { throw NativeExecutionError.changed }
        return Self.hash(data)
    }
    func remove(_ path: String) throws {
        let parts = try components(path)
        guard let name = parts.last else { throw NativeExecutionError.invalidRequest }
        let parent = try directory(Array(parts.dropLast()), create: false); defer { close(parent) }
        guard unlinkat(parent, name, 0) == 0 || errno == ENOENT else { throw NativeExecutionError.accessDenied }
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
