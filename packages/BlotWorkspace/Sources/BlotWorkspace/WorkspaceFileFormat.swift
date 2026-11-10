import Foundation

enum WorkspaceFileFormat {
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "tsv", "json", "swift", "java", "py", "js", "ts", "tsx", "jsx", "html", "css", "c", "cpp", "h", "rs", "go", "sh", "yaml", "yml", "sql", "kt", "rb", "toml", "xml", "log"]
    static func mediaType(forExtension ext: String) throws -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "webp": return "image/webp"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "tsv": return "text/tab-separated-values"
        case "md", "markdown": return "text/markdown"
        default:
            guard textExtensions.contains(ext.lowercased()) else { throw WorkspaceFileError.unsupportedType }
            return "text/plain"
        }
    }
    static func fileExtension(_ mediaType: String) -> String {
        switch mediaType {
        case "application/pdf": "pdf"
        case "application/json": "json"
        case "text/csv": "csv"
        case "text/tab-separated-values": "tsv"
        case "text/markdown": "md"
        case "image/png": "png"
        case "image/jpeg": "jpg"
        case "image/heic", "image/heif": "heic"
        case "image/tiff": "tiff"
        case "image/webp": "webp"
        default: "txt"
        }
    }
    static func isText(_ type: String) -> Bool { type.hasPrefix("text/") || type == "application/json" }
}
