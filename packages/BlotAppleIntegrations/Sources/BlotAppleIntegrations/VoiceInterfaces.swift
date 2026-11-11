import Foundation

public enum VoiceFailure: Error, LocalizedError, Equatable {
    case microphoneDenied, languageUnavailable, voiceUnavailable, audioUnavailable, audioOverrun, interrupted, emptyResponse
    public var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Разрешите микрофон для Blot в системных настройках."
        case .languageUnavailable: "Локальное распознавание этого языка недоступно на устройстве."
        case .voiceUnavailable: "На устройстве нет голоса для выбранного языка."
        case .audioUnavailable: "Не удалось включить аудиоустройство. Проверьте микрофон и наушники."
        case .audioOverrun: "Устройство не успевает распознавать звук. Начните разговор заново."
        case .interrupted: "Аудиоустройство изменилось или разговор был прерван. Начните разговор заново."
        case .emptyResponse: "Ответ не завершён. Проверьте результат в чате перед повтором запроса."
        }
    }
}

@MainActor public protocol VoiceRecognizing: AnyObject {
    func prepare(locale: Locale) async throws
    func start(update: @escaping @MainActor (String) -> Void, activity: @escaping @MainActor () -> Void,
               failure: @escaping @MainActor (Error) -> Void) async throws
    func finish() async throws -> String
    func stop() async
}
@MainActor public protocol VoiceSpeaking: AnyObject {
    func prepare(locale: Locale) throws
    func speak(_ text: String) async throws
    func stop()
}

/// Speech modules may revise an overlapping interval before finalizing it.
public struct VoiceTranscript: Sendable {
    private struct Segment: Sendable { let start: Double; let end: Double; let text: String }
    private var segments: [Segment] = []
    public init() {}
    public mutating func replace(start: Double, end: Double, text: String) {
        guard start.isFinite, end.isFinite, end >= start else { return }
        segments.removeAll { abs($0.start - start) < 0.001 || ($0.start < end && $0.end > start) }
        let text = String(text.prefix(10_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { segments.append(.init(start: start, end: end, text: text)) }
        segments.sort { $0.start < $1.start }
        if segments.count > 128 { segments.removeFirst(segments.count - 128) }
    }
    public var text: String { String(segments.map(\.text).joined(separator: " ").prefix(10_000)) }
}

public enum VoiceSpokenText {
    /// Keep long code, tables and links on screen instead of reading their syntax aloud.
    public static func prepare(_ text: String, russian: Bool) -> String {
        var inCode = false
        let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle(); return nil }
            guard !inCode, !line.trimmingCharacters(in: .whitespaces).hasPrefix("|") else { return nil }
            return line
        }
        var value = lines.joined(separator: " ")
        value = value.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[*#`_>]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return russian ? "Результат показан в чате." : "The result is shown in the chat." }
        if value.count > 1800 {
            value = String(value.prefix(1600))
            if let last = value.lastIndex(where: { ".!?".contains($0) }) { value = String(value[...last]) }
            value += russian ? " Полный ответ — в чате." : " The full reply is in the chat."
        }
        return value
    }
}
