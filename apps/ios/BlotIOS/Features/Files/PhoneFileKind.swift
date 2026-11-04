import Foundation
import SwiftUI

enum PhoneFileKind: Equatable {
    case document, code, image, spreadsheet, presentation, pdf, audio, video, archive, other

    init(name: String, mediaType: String) {
        let fileExtension = (name as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "swift", "py", "js", "jsx", "ts", "tsx", "html", "css", "scss", "json", "xml", "yaml", "yml", "toml", "sh", "zsh", "bash", "sql", "java", "kt", "kts", "go", "rs", "c", "h", "cpp", "hpp", "cs", "rb", "php", "vue", "svelte", "dart": self = .code
        case "md", "markdown", "txt", "rtf", "doc", "docx", "odt", "pages": self = .document
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "svg", "tiff", "bmp", "avif": self = .image
        case "csv", "tsv", "xls", "xlsx", "ods", "numbers": self = .spreadsheet
        case "ppt", "pptx", "odp", "key": self = .presentation
        case "pdf": self = .pdf
        case "mp3", "wav", "m4a", "aac", "aiff", "flac", "ogg": self = .audio
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": self = .video
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz": self = .archive
        default:
            let mime = mediaType.lowercased()
            if mime.hasPrefix("image/") { self = .image }
            else if mime.hasPrefix("audio/") { self = .audio }
            else if mime.hasPrefix("video/") { self = .video }
            else if mime == "application/pdf" { self = .pdf }
            else if mime.hasPrefix("text/") { self = .document }
            else { self = .other }
        }
    }

    var symbol: String {
        switch self {
        case .document: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        case .spreadsheet: "tablecells"
        case .presentation: "rectangle.on.rectangle"
        case .pdf: "doc.richtext"
        case .audio: "waveform"
        case .video: "film"
        case .archive: "doc.zipper"
        case .other: "doc"
        }
    }

    var color: Color {
        switch self {
        case .document: .blue
        case .code: .purple
        case .image: .pink
        case .spreadsheet: .green
        case .presentation, .archive: .orange
        case .pdf: .red
        case .audio: .teal
        case .video: .indigo
        case .other: .secondary
        }
    }
}
