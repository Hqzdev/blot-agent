import BlotDomain
import Foundation

public enum WorkspaceGroupMentions {
    /// A name referenced inside a result is not a request for another agent to run again.
    public static func recipients(_ text: String, mentions: [BlotV3.MessageMention]) -> Set<UUID> {
        let value = text as NSString
        return Set(mentions.filter { mention in
            guard mention.startUTF16 < value.length, value.character(at: mention.startUTF16) == 64 else { return false }
            let prefix = value.substring(to: mention.startUTF16)
            return (prefix.components(separatedBy: .newlines).last ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }.map(\.agentId))
    }
    public static func extract(_ text: String, agents: [BlotV3.AgentProfile]) throws -> [BlotV3.MessageMention] {
        let textRange = NSRange(location: 0, length: text.utf16.count)
        var mentions: [BlotV3.MessageMention] = []
        for agent in agents.sorted(by: { $0.name.count > $1.name.count }) {
            let pattern = "@" + NSRegularExpression.escapedPattern(for: agent.name) + "(?![\\p{L}\\p{N}_])"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for match in regex.matches(in: text, range: textRange) {
                guard !mentions.contains(where: { NSIntersectionRange(NSRange(location: $0.startUTF16, length: $0.lengthUTF16), match.range).length > 0 }) else { continue }
                mentions.append(try .init(agentId: agent.metadata.id, startUTF16: match.range.location, lengthUTF16: match.range.length))
            }
        }
        return mentions.sorted { $0.startUTF16 < $1.startUTF16 }
    }
}
