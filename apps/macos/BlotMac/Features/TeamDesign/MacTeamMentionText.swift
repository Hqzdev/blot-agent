import AppKit
import BlotDesign
import SwiftUI

struct MacTeamMentionText: View {
    let source: String
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.colorScheme) private var scheme

    var body: some View { formatted }

    private var formatted: Text {
        MacDemoMessageText.segments(source).reduce(Text("")) { result, segment in
            switch segment {
            case .text(let text): return Text("\(result)\(Text(verbatim: text))")
            case .agent(let id):
                guard let agent = presentation.agents.first(where: { $0.id == id }) else {
                    return Text("\(result)@Удалённый агент")
                }
                let name = Text(verbatim: "@" + agent.name.replacingOccurrences(of: " ", with: "\u{00a0}")).fontWeight(.semibold)
                    .foregroundColor(WorkspaceAvatarView.color(agent.color))
                if let avatar = MacTeamInlineAvatarCache.shared.image(for: agent, scheme: scheme) {
                    let icon = Text(Image(nsImage: avatar).renderingMode(.original)).baselineOffset(-3)
                    return Text("\(result)\(name)\u{00a0}\(icon)")
                }
                return Text("\(result)\(name)")
            }
        }
    }
}

@MainActor private final class MacTeamInlineAvatarCache {
    static let shared = MacTeamInlineAvatarCache()
    private let images = NSCache<NSString, NSImage>()

    private init() { images.countLimit = 100 }

    func image(for agent: MacTeamAgent, scheme: ColorScheme) -> NSImage? {
        let key = "\(agent.id)|\(agent.avatarShape)|\(agent.color)|\(agent.avatarData?.hashValue ?? 0)|\(scheme)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        let renderer = ImageRenderer(content: MacTeamAvatar(agent: agent, size: 18).environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}
