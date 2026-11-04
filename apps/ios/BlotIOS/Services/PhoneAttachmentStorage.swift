import Foundation

actor PhoneAttachmentStorage {
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Blot/Attachments", isDirectory: true)

    func savePhoto(_ data: Data, fileExtension: String) throws -> URL {
        let destination = try destination(for: "Photo.\(fileExtension)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func importFile(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let destination = try destination(for: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func destination(for name: String) throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}

enum PhoneAttachmentError: String, LocalizedError {
    case cameraUnavailable = "No camera is available."
    case cameraDenied = "Allow camera access in iPhone Settings to take a photo."
    case photoUnavailable = "The selected photo could not be loaded."

    var errorDescription: String? { rawValue }
}
