import Foundation
import BlotAppleIntegrations
import BlotDomain
import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspaceMessageText: View {
    let text: String
    var markdown = true
    var agents: [BlotV3.AgentProfile] = []
    var skills: [BlotV3.Skill] = []
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var avatarSize = 14

    var body: some View {
        WorkspaceRenderedTextCache.text(text, markdown: markdown, agents: agents, skills: skills,
            size: avatarSize, scale: displayScale, scheme: scheme) { renderedText }
    }

    private var renderedText: Text {
        let content = WorkspaceMarkdownCache.content(text, markdown: markdown)
        let plain = String(content.characters)
        let agentNames = Set(agents.map { $0.name.lowercased() })
        let peopleAndSkills = agents.map(WorkspaceInlineMention.agent) + skills.filter { !$0.archived && !agentNames.contains($0.name.lowercased()) }.map(WorkspaceInlineMention.skill)
        let reservedNames = Set(peopleAndSkills.map { $0.name.lowercased() })
        let targets = peopleAndSkills + WorkspacePluginReference.all.filter { !reservedNames.contains($0.name.lowercased()) }.map(WorkspaceInlineMention.plugin)
        let byID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        guard !targets.isEmpty, let references = try? WorkspaceNamedReferences.find(plain, names: byID.mapValues(\.name)), !references.isEmpty else { return Text(content) }
        var result: [Text] = []
        result.reserveCapacity(references.count * 4 + 1)
        var cursor = content.startIndex
        for reference in references {
            guard let range = Range(NSRange(location: reference.startUTF16, length: reference.lengthUTF16), in: plain),
                  let target = byID[reference.id] else { continue }
            if case .plugin = target, plain[range.lowerBound] != "@" { continue }
            let start = content.characters.index(content.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: range.lowerBound))
            let end = content.characters.index(start, offsetBy: plain.distance(from: range.lowerBound, to: range.upperBound))
            // Keep code and existing links intact.
            guard !content[start..<end].runs.contains(where: { $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true }) else { continue }
            result.append(Text(AttributedString(content[cursor..<start])))
            let name = Text(verbatim: target.displayName).foregroundColor(target.color).fontWeight(.semibold)
            switch target {
            case .agent(let agent):
                if let image = WorkspaceMentionAvatar.image(agent: agent, size: avatarSize, scale: displayScale, scheme: scheme) {
                    let avatar = Text(image).baselineOffset(-2)
                    result.append(avatar); result.append(Text(verbatim: "\u{202F}"))
                }
            case .skill:
                let avatar = Text(Image(systemName: "shippingbox")).foregroundColor(target.color)
                result.append(avatar); result.append(Text(verbatim: "\u{202F}"))
            case .plugin(let plugin):
                if let image = WorkspaceMentionAvatar.image(plugin: plugin, size: avatarSize, scale: displayScale, scheme: scheme) {
                    let logo = Text(image).baselineOffset(-2)
                    result.append(logo); result.append(Text(verbatim: "\u{202F}"))
                }
            }
            result.append(name)
            cursor = end
        }
        result.append(Text(AttributedString(content[cursor..<content.endIndex])))
        return WorkspaceJoinedText.join(result[...])
    }
}

/// A balanced native Text tree avoids recursively localizing the accumulated message.
/// Text concatenation retains inline images and styles without a localized format at every mention.
private enum WorkspaceJoinedText {
    static func join(_ parts: ArraySlice<Text>) -> Text {
        guard !parts.isEmpty else { return Text(verbatim: "") }
        if parts.count == 1 { return parts[parts.startIndex] }
        let middle = parts.index(parts.startIndex, offsetBy: parts.count / 2)
        return join(parts[..<middle]) + join(parts[middle...])
    }
}

/// Both caches are bounded; typography, appearance and mention identities are part of the rendered key.
@MainActor
private enum WorkspaceRenderedTextCache {
    private struct Input: Hashable {
        let text: String
        let markdown: Bool
        let targets: [String]
        let size: CGFloat
        let scale: CGFloat
        let dark: Bool
    }
    private final class Key: NSObject {
        let input: Input
        init(_ input: Input) { self.input = input }
        override var hash: Int { input.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? Key)?.input == input }
    }
    private final class Value {
        let text: Text
        init(_ text: Text) { self.text = text }
    }
    private static let cache: NSCache<Key, Value> = {
        let cache = NSCache<Key, Value>(); cache.countLimit = 256; cache.totalCostLimit = 8 * 1024 * 1024; return cache
    }()
    static func text(_ text: String, markdown: Bool, agents: [BlotV3.AgentProfile], skills: [BlotV3.Skill],
                     size: CGFloat, scale: CGFloat, scheme: ColorScheme, render: () -> Text) -> Text {
        let targets = agents.flatMap { [$0.metadata.id.uuidString, $0.name, $0.avatarShape, $0.avatarColor] }
            + skills.filter { !$0.archived }.flatMap { [$0.metadata.id.uuidString, $0.name] }
        let key = Key(Input(text: text, markdown: markdown, targets: targets, size: size, scale: scale, dark: scheme == .dark))
        if let value = cache.object(forKey: key) { return value.text }
        let value = render()
        cache.setObject(Value(value), forKey: key, cost: text.utf8.count * 6 + targets.reduce(0) { $0 + $1.utf8.count } + 4096)
        return value
    }
}

@MainActor
enum WorkspaceMarkdownCache {
    private final class Value {
        let content: AttributedString
        init(_ content: AttributedString) { self.content = content }
    }
    private static let cache: NSCache<NSString, Value> = {
        let cache = NSCache<NSString, Value>(); cache.countLimit = 256; cache.totalCostLimit = 4 * 1024 * 1024; return cache
    }()
    static func content(_ text: String, markdown: Bool = true) -> AttributedString {
        guard markdown else { return AttributedString(text) }
        if let value = cache.object(forKey: text as NSString) { return value.content }
        let content = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        cache.setObject(Value(content), forKey: text as NSString, cost: text.utf8.count * 3 + 256)
        return content
    }
}

@MainActor
private enum WorkspaceMentionAvatar {
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>(); cache.countLimit = 128; return cache
    }()
    static func image(agent: BlotV3.AgentProfile, size: CGFloat, scale: CGFloat, scheme: ColorScheme) -> Image? {
        let key = "\(agent.avatarShape):\(agent.avatarColor):\(size):\(scale):\(scheme)" as NSString
        if let image = cache.object(forKey: key) { return Image(decorative: image, scale: scale) }
        let renderer = ImageRenderer(content: WorkspaceAvatar(shape: .init(rawValue: agent.avatarShape) ?? .round,
            color: WorkspaceAvatarPalette.color(agent.avatarColor), size: size).environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        cache.setObject(image, forKey: key)
        return Image(decorative: image, scale: scale)
    }
    static func image(plugin: WorkspacePluginReference, size: CGFloat, scale: CGFloat, scheme: ColorScheme) -> Image? {
        let key = "plugin:\(plugin.entry.id):\(size):\(scale):\(scheme)" as NSString
        if let image = cache.object(forKey: key) { return Image(decorative: image, scale: scale) }
        let renderer = ImageRenderer(content: WorkspacePluginLogo(plugin: plugin, size: size).environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        cache.setObject(image, forKey: key)
        return Image(decorative: image, scale: scale)
    }
}

private enum WorkspaceInlineMention {
    case agent(BlotV3.AgentProfile), skill(BlotV3.Skill), plugin(WorkspacePluginReference)
    var id: String { switch self { case .agent(let value): "agent:" + value.metadata.id.uuidString; case .skill(let value): "skill:" + value.metadata.id.uuidString; case .plugin(let value): "plugin:" + value.id } }
    var name: String { switch self { case .agent(let value): value.name; case .skill(let value): value.name; case .plugin(let value): value.name } }
    var displayName: String { if case .plugin = self { "@" + name } else { name } }
    var color: Color { switch self { case .agent(let value): WorkspaceAvatarPalette.color(value.avatarColor); case .skill: WorkspaceAvatarPalette.color("purple"); case .plugin(let value): value.color } }
}
