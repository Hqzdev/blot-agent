import Foundation

enum WorkspacePersonalizedReply {
    static func format(_ source: String, preferences: WorkspacePersonalization, language: String,
                       contextNotes: [String] = []) -> String {
        let russian = language == "ru"
        var text = source
        switch preferences.length {
        case .concise:
            let paragraphs = source.components(separatedBy: "\n\n")
            let paragraph = paragraphs.first ?? source
            if paragraph.hasSuffix(":"), paragraphs.count > 1 {
                text = paragraphs[1].components(separatedBy: "\n").prefix(2).joined(separator: "\n")
            } else {
                let sentences = paragraph.components(separatedBy: ". ")
                text = sentences.prefix(2).joined(separator: ". ")
                if sentences.count > 2, !text.hasSuffix(".") { text += "." }
            }
        case .standard: break
        case .detailed:
            text += russian
                ? "\n\nКритерии готовности:\n1. Результат отвечает исходной задаче.\n2. Важные допущения и ограничения указаны.\n3. Следующий шаг понятен и согласован."
                : "\n\nCompletion criteria:\n1. The result addresses the original task.\n2. Important assumptions and constraints are explicit.\n3. The next step is clear and agreed."
        }
        switch preferences.tone {
        case .friendly: text = (russian ? "Давайте разберёмся вместе.\n\n" : "Let’s work through this together.\n\n") + text
        case .professional: break
        case .strict:
            text = text.replacingOccurrences(of: "Предлагаю", with: "Нужно")
                .replacingOccurrences(of: "предлагаю", with: "нужно")
                .replacingOccurrences(of: "Что для вас важнее всего в результате?", with: "Укажите приоритет результата.")
                .replacingOccurrences(of: "What matters most to you in the result?", with: "State the priority for the result.")
                .replacingOccurrences(of: "Let’s", with: "We will")
            text = (russian ? "По существу.\n\n" : "Directly to the point.\n\n") + text
        }
        if !contextNotes.isEmpty { text += "\n\n" + contextNotes.joined(separator: "\n") }
        if preferences.format == .plain {
            text = text.replacingOccurrences(of: #"(?m)^[ \t]*(?:\d+[.)]|[-*+])[ \t]+"#, with: "", options: .regularExpression)
        } else {
            let heading = russian ? "Ответ" : "Response"
            text = "**\(heading)**\n\n" + text
        }
        if preferences.format == .expressive {
            text += preferences.tone == .friendly ? " 🙂" : " ✅"
        } else {
            text = String(text.filter { character in
                !character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x20E3 }
            })
        }
        return text
    }
}
