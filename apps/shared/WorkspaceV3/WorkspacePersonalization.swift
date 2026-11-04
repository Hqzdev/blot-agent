import Foundation

nonisolated struct WorkspacePersonalization: Codable, Equatable, Sendable {
    enum Tone: String, Codable, CaseIterable, Identifiable, Sendable {
        case friendly = "Friendly", professional = "Professional", strict = "Strict"
        var id: String { rawValue }
    }
    enum Length: String, Codable, CaseIterable, Identifiable, Sendable {
        case concise = "Concise", standard = "Medium", detailed = "Detailed"
        var id: String { rawValue }
    }
    enum Format: String, Codable, CaseIterable, Identifiable, Sendable {
        case expressive = "Markdown and emoji", markdown = "Markdown without emoji", plain = "Plain text"
        var id: String { rawValue }
    }

    var tone = Tone.professional
    var length = Length.standard
    var format = Format.markdown

    var instruction: String {
        let voice: String
        switch tone {
        case .friendly: voice = "Use a friendly, approachable voice."
        case .professional: voice = "Use a calm, professional voice."
        case .strict: voice = "Be direct and strict. Avoid pleasantries and filler."
        }
        let detail: String
        switch length {
        case .concise: detail = "Keep the answer concise: give the main result and essential next step."
        case .standard: detail = "Use a medium amount of detail with the key explanation and next steps."
        case .detailed: detail = "Give a detailed explanation, actionable steps and completion criteria."
        }
        let styling: String
        switch format {
        case .expressive: styling = "Use Markdown where helpful and a small number of relevant emoji."
        case .markdown: styling = "Use Markdown where helpful. Do not use emoji."
        case .plain: styling = "Use plain text only. Do not use Markdown or emoji."
        }
        return [voice, detail, styling, "These are response style preferences for every agent. Preserve the agent's role and task instructions."].joined(separator: " ")
    }
}
