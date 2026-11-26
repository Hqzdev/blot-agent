import Foundation

/// A short status describes a validated pending call, never a claimed result.
enum WorkspaceToolProgress {
    static func message(for call: ChatToolCall, request: String) -> String? {
        let russian = request.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) != nil
        let fields = call.arguments.mcpFields
        let target = fields["path"]?.mcpString ?? fields["title"]?.mcpString
        let suffix = target.map { " «" + String($0.prefix(160)) + "»" } ?? ""
        let verb: String
        switch call.name {
        case "workspace_directory": return russian ? "Проверяю рабочую папку." : "Checking the workspace folder."
        case "workspace_list_files": verb = russian ? "Проверяю файлы" : "Listing files"
        case "workspace_read_file": verb = russian ? "Читаю файл" : "Reading file"
        case "workspace_write_file": verb = russian ? "Сохраняю файл" : "Saving file"
        case "workspace_create_directory": verb = russian ? "Создаю папку" : "Creating folder"
        case "document_create": verb = russian ? "Создаю документ" : "Creating document"
        default: return nil
        }
        return verb + suffix + "."
    }
}
