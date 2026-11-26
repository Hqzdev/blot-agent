import Foundation

/// Recognizes read and access checks that should begin with an actual mail tool.
struct WorkspaceMailRequest {
    enum Action { case access, recent, read }
    private enum Provider { case automatic, gmail, apple }
    let action: Action
    private let provider: Provider
    private let request: String

    static func isRetry(_ text: String) -> Bool {
        text.lowercased().range(of: #"^\s*(?:(?:а )?сейчас|попробуй (?:еще|ещё) раз|(?:and )?now|try again)[\s?!.,]*$"#,
            options: .regularExpression) != nil
    }

    init?(_ request: String, previous: String? = nil) {
        let text = request.lowercased()
        func matches(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        if Self.isRetry(text), let previous, let original = Self(previous) {
            self = original
            return
        }
        guard !matches(#"^\s*(?:как\b|how\b|объясни\b|расскажи\b)|(?:\bне\s+|do not |don.t )(?:читай|проверяй|смотри|открывай|ищи|read|check|open|search)"#),
              matches(#"gmail|джимейл|apple\s+mail|эпл\s+почт|почт[аыуеой]|письм|писем|входящ|\b(?:e-?mails?|inbox|mailbox|mail)\b"#) else { return nil }
        guard !matches(#"(?:отправь|перешли|ответь|черновик|напиши(?:те)?\s+письмо|\b(?:send|forward|reply|draft|compose)\b)"#) else { return nil }
        let filtered = matches(#"непрочитан|в\s+отправленн|(?:письм\p{L}*|писем)\s+(?:от|из|про|за|с\s+темой)|\b(?:from|subject|unread|sent):|\b(?:messages?|e-?mails?)\s+from\b"#)
        let followsEarlierInboxRequest = matches(#"^\s*(?:к\s+)?(?:gmail|джимейл|apple\s+mail)[ \t]+(?:посмотри|проверь|покажи)[\s?!.,]*$"#)
            && previous.flatMap { Self($0)?.action } == .recent
        if matches(#"(?:провер\p{L}*|посмотр\p{L}*|есть\s+ли|\bcheck\b|\bverify\b|\bdo you have\b)[^.!?\n]{0,80}(?:доступ|подключ|access|connected)"#),
           !matches(#"последн|непрочитан|(?:и|затем)\s+(?:найди|прочитай|покажи|создай|проверь)|\b(?:latest|recent|unread|then)\b"#) {
            action = .access
        } else if !filtered && (followsEarlierInboxRequest || matches(#"последн|самых\s+новых|\b(?:latest|recent|newest)\b"#)) {
            action = .recent
        } else if matches(#"посмотр|проверь|покажи|прочитай|открой|найди|входящ|последн|\b(?:check|show|read|open|find|search|list)\b"#) {
            action = .read
        } else { return nil }
        provider = matches(#"gmail|джимейл"#) ? .gmail : matches(#"apple\s+mail|эпл\s+почт"#) ? .apple : .automatic
        self.request = (followsEarlierInboxRequest ? previous ?? request : request).lowercased()
    }

    func requiredTool(available: Set<String>, results: [(name: String, value: ChatJSON)]) -> String? {
        if let resources = results.last(where: { $0.name == "apple_mail_resources" }) {
            guard action != .access, case .array(let values) = resources.value, values.count == 1,
                  available.contains("apple_mail_list"), !results.contains(where: { $0.name == "apple_mail_list" }) else { return nil }
            return "apple_mail_list"
        }
        if let accounts = results.last(where: { $0.name == "google_accounts" }) {
            guard case .array(let entries) = accounts.value else { return nil }
            let gmail = entries.filter { $0.mcpFields["service"] == .string("gmail") }
            let specifiedAccount = request.range(of: #"(?:(?:аккаунт\p{L}*|ящик\p{L}*|почт\p{L}*|\baccount)\s+|^)[\w.+-]+@[\w.-]+\.[a-z]{2,}"#, options: .regularExpression)
            let named = gmail.filter { entry in
                guard let specifiedAccount, let email = entry.mcpFields["email"]?.mcpString else { return false }
                return request[specifiedAccount].split(separator: " ").last == email.lowercased()[...]
            }
            guard specifiedAccount != nil ? named.count == 1 : gmail.count == 1 else { return nil }
            let next = action == .access ? "gmail_check_access" : action == .recent ? "gmail_recent" : "gmail_search"
            return available.contains(next) && !results.contains(where: { $0.name == next }) ? next : nil
        }
        if provider != .apple, available.contains("google_accounts"),
           available.contains(action == .access ? "gmail_check_access" : action == .recent ? "gmail_recent" : "gmail_search") {
            return "google_accounts"
        }
        if provider != .gmail, available.contains("apple_mail_resources") { return "apple_mail_resources" }
        return available.contains("plugin_catalog") && !results.contains(where: { $0.name == "plugin_catalog" })
            ? "plugin_catalog" : nil
    }

    var instruction: String {
        let target = provider == .gmail ? "Gmail" : provider == .apple ? "Apple Mail" : "the available inbox (prefer Gmail when both are available)"
        let operation = switch action {
        case .access: "Verify access without inspecting any messages. Check the Gmail profile or discover Apple Mail resources."
        case .recent: "Fetch the latest requested number of inbox messages, newest first. Report sender, subject and date from the result. The count must match the user's request within the tool's limit. For explicit searches include the user's filters."
        case .read: "Inspect the requested inbox or search for the requested messages. For an unfiltered Gmail inbox search use query in:inbox. Continue to fetch the details needed for the answer."
        }
        let catalog = provider == .gmail ? "query gmail" : provider == .apple ? "query apple.mail" : "omit query to see mail providers"
        return "For this mail task, use \(target). \(operation) In plugin_catalog \(catalog). If the latest message is a retry, carry forward the earlier read request, count and filters."
    }
}
