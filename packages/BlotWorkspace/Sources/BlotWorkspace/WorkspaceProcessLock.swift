import Darwin
import Foundation

/// The lock lives for the whole execution session. A second app process cannot recover or run its work.
public final class WorkspaceProcessLock: @unchecked Sendable {
    private let descriptor: Int32
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = Darwin.open(directory.appendingPathComponent("execution.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw WorkspaceStorageError.permissionDenied }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw WorkspaceStorageError.permissionDenied
        }
        self.descriptor = descriptor
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
