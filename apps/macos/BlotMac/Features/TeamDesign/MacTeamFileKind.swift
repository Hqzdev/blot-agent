import Foundation

nonisolated enum MacTeamFileKind {
    case document, spreadsheet, presentation, code

    init(filename: String) {
        let suffix = (filename.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).pathExtension.lowercased()
        switch suffix {
        case "csv", "tsv", "xls", "xlsx", "xlsm", "ods", "numbers", "gsheet":
            self = .spreadsheet
        case "ppt", "pptx", "pps", "ppsx", "odp", "key", "gslides":
            self = .presentation
        case "swift", "py", "pyw", "js", "mjs", "cjs", "ts", "tsx", "jsx", "java",
             "kt", "kts", "go", "rs", "rb", "php", "html", "htm", "css", "scss", "sass",
             "less", "sql", "sh", "zsh", "bash", "c", "cpp", "cc", "cxx", "h", "hpp",
             "m", "mm", "cs", "json", "yaml", "yml", "toml", "xml", "ipynb", "vue", "svelte":
            self = .code
        default:
            self = .document
        }
    }

    var assetName: String {
        switch self {
        case .document: "FileGoogleDocs"
        case .spreadsheet: "FileGoogleSheets"
        case .presentation: "FileGoogleSlides"
        case .code: "FileVSCode"
        }
    }

    var title: String {
        switch self {
        case .document: "Документ"
        case .spreadsheet: "Таблица"
        case .presentation: "Презентация"
        case .code: "Код"
        }
    }
}
