import BlotDesign
import Foundation

enum LocalPreviewError: LocalizedError {
    case directory, tooLarge, unsupported
    var errorDescription: String? {
        switch self {
        case .directory: "Choose a file rather than a folder."
        case .tooLarge: "Local previews support files up to 10 MB."
        case .unsupported: "This file does not contain a supported image, PDF or UTF-8 text."
        }
    }
}

enum LocalPreviewReader {
    nonisolated static func read(_ url: URL, maxBytes: Int? = nil) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard values.isDirectory != true else { throw LocalPreviewError.directory }
        if let maxBytes, (values.fileSize ?? 0) > maxBytes { throw LocalPreviewError.tooLarge }
        return try Data(contentsOf: url)
    }
}
