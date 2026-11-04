import Foundation

/// Stable IDs in mentions keep the displayed name, color and avatar in sync with the agent profile.
nonisolated enum MacDemoMessageText {
    enum Segment: Equatable {
        case text(String)
        case agent(String)
    }

    static func mention(_ agentID: String) -> String { "@{" + agentID + "}" }

    static func segments(_ source: String) -> [Segment] {
        var remainder = source[...]
        var result: [Segment] = []
        while let start = remainder.range(of: "@{"),
              let end = remainder[start.upperBound...].firstIndex(of: "}") {
            if start.lowerBound > remainder.startIndex {
                result.append(.text(String(remainder[..<start.lowerBound])))
            }
            let id = String(remainder[start.upperBound..<end])
            result.append(id.isEmpty ? .text("@{}") : .agent(id))
            remainder = remainder[remainder.index(after: end)...]
        }
        if !remainder.isEmpty { result.append(.text(String(remainder))) }
        return result
    }

    static func plain(_ source: String, agents: [MacDemoAgent]) -> String {
        segments(source).map {
            switch $0 {
            case .text(let text): text
            case .agent(let id): "@" + (agents.first { $0.id == id }?.name ?? "Удалённый агент")
            }
        }.joined()
    }
}

nonisolated struct MacDemoReaction: Codable, Equatable, Sendable {
    static let userID = "user"
    static let choices = ["👍", "❤️", "😂", "🔥", "✅", "👀"]
    let emoji: String
    let authorID: String
}
