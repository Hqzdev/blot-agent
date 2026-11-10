import Foundation

/// Matches a localized UI format while preserving the inserted names, numbers and paths.
struct WorkspaceCopyTemplate {
    private static let placeholder = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+0 #]*\d*(?:\.\d+)?(?:ll|l)?[@difu]"#)
    private let expression: NSRegularExpression
    private let translation: String

    init?(source: String, translation: String) {
        let range = NSRange(source.startIndex..., in: source)
        let tokens = Self.placeholder.matches(in: source, range: range)
        guard !tokens.isEmpty else { return nil }
        var pattern = "^"
        var cursor = source.startIndex
        for token in tokens {
            guard let tokenRange = Range(token.range, in: source) else { return nil }
            pattern += NSRegularExpression.escapedPattern(for: String(source[cursor..<tokenRange.lowerBound]))
            pattern += "(.+?)"
            cursor = tokenRange.upperBound
        }
        pattern += NSRegularExpression.escapedPattern(for: String(source[cursor...])) + "$"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        self.expression = expression
        self.translation = translation
    }

    func translate(_ source: String) -> String? {
        guard let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        let arguments = (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: source).map { String(source[$0]) } ?? ""
        }
        var output = translation
        let tokens = Self.placeholder.matches(in: translation, range: NSRange(translation.startIndex..., in: translation))
        for (index, token) in tokens.enumerated().reversed() {
            let position = Range(token.range(at: 1), in: translation).flatMap { Int(translation[$0]) }.map { $0 - 1 } ?? index
            guard arguments.indices.contains(position), let range = Range(token.range, in: output) else { return nil }
            output.replaceSubrange(range, with: arguments[position])
        }
        return output.replacingOccurrences(of: "%%", with: "%")
    }
}
