import AppKit
import BlotDesign
import SwiftUI

struct MacTeamAvatar: View {
    let agent: MacTeamAgent
    var size: CGFloat = 36
    var body: some View {
        Group {
            if let data = agent.avatarData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                WorkspaceAvatar(shape: agent.shape, color: WorkspaceAvatarView.color(agent.color), size: size)
            }
        }
    }
}

struct MacTeamIconButton: View {
    let title: String
    let symbol: String
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            BlotIcon(symbol: symbol, size: BlotIconSize.control).frame(width: 28, height: 28)
                .background(WorkspaceStyle.ink.opacity(hovered ? 0.055 : 0), in: Circle()).contentShape(Circle())
        }
        .buttonStyle(BlotPlainButtonStyle()).foregroundStyle(WorkspaceStyle.ink).help(title).accessibilityLabel(title)
        .onHover { hovered = $0 }.kAnimation(KMotion.quick, value: hovered)
    }
}

struct MacTeamSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 25, weight: .semibold))
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacTeamBadge: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.09), in: Capsule())
            .contentTransition(.opacity).kAnimation(KMotion.quick, value: text)
    }
}

struct MacTeamPluginIcon: View {
    let plugin: MacTeamPlugin
    var size: CGFloat = 38
    var body: some View {
        Image(plugin.assetName).renderingMode(.original)
            .resizable().scaledToFit().padding(size * 0.16)
            .frame(width: size, height: size)
            .background(.white, in: RoundedRectangle(cornerRadius: size * 0.26))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(BlotColor.edge.opacity(0.65))
            }
            .accessibilityHidden(true)
    }
}

struct MacTeamSheetHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            MacTeamIconButton(title: "Закрыть", symbol: "xmark") { dismiss() }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }
}

extension View {
    func teamCard(padding: CGFloat = 16) -> some View {
        self.padding(padding).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BlotColor.edge.opacity(0.7)))
    }
}
