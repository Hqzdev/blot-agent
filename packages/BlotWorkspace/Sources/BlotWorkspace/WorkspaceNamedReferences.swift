import Foundation

/// Finds complete known names in display text, choosing longer names before overlapping ones.
public enum WorkspaceNamedReferences {
    private static let expressions = ExpressionCache()
    public struct NamedReference<ID: Hashable & Sendable>: Sendable {
        public let id: ID
        public let startUTF16: Int
        public let lengthUTF16: Int
    }
    public typealias Reference = NamedReference<UUID>
    public static func find<ID: Hashable & Sendable>(_ text: String, names: [ID: String]) throws -> [NamedReference<ID>] {
        let textRange = NSRange(location: 0, length: text.utf16.count)
        var references: [NamedReference<ID>] = []
        let ordered = names.sorted { $0.value.count == $1.value.count ? String(describing: $0.key) < String(describing: $1.key) : $0.value.count > $1.value.count }
        for (id, name) in ordered where !name.isEmpty {
            let pattern = #"(?<![\p{L}\p{N}_@./])@?"# + NSRegularExpression.escapedPattern(for: name)
                + #"(?![\p{L}\p{N}_@]|[./][\p{L}\p{N}])"#
            let regex = try expressions.expression(pattern)
            for match in regex.matches(in: text, range: textRange) {
                guard !references.contains(where: { NSIntersectionRange(NSRange(location: $0.startUTF16, length: $0.lengthUTF16), match.range).length > 0 }) else { continue }
                references.append(.init(id: id, startUTF16: match.range.location, lengthUTF16: match.range.length))
            }
        }
        return references.sorted { $0.startUTF16 < $1.startUTF16 }
    }

    /// NSCache is thread-safe; each immutable expression can serve concurrent model/UI readers.
    private final class ExpressionCache: @unchecked Sendable {
        private let cache = NSCache<NSString, NSRegularExpression>()
        init() { cache.countLimit = 512; cache.totalCostLimit = 512 * 1024 }
        func expression(_ pattern: String) throws -> NSRegularExpression {
            if let expression = cache.object(forKey: pattern as NSString) { return expression }
            let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            cache.setObject(expression, forKey: pattern as NSString, cost: pattern.utf8.count + 512)
            return expression
        }
    }
}
