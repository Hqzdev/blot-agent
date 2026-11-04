import BlotDesign
import SwiftUI

struct MacTeamHeader: View {
    var leadingInset: CGFloat = 18
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var headerWidth: CGFloat = 800

    private var profileWidth: CGFloat {
        max(100, min(240, headerWidth - 2 * (leadingInset + 78 + 18)))
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack(alignment: .top) {
                if presentation.isConversation {
                    profile.frame(width: profileWidth).frame(maxWidth: .infinity)
                } else {
                    titleLabel
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity)
                }
                HStack(alignment: .top) {
                    MacTeamWindowControls()
                    Spacer(minLength: 20)
                    if presentation.isConversation {
                        Button { presentation.inspectorVisible.toggle() } label: {
                            BlotIcon(.inspector, size: BlotIconSize.control)
                                .foregroundStyle(WorkspaceStyle.ink).frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .help(presentation.inspectorVisible ? "Скрыть панель агента" : "Показать панель агента")
                        .accessibilityLabel(presentation.inspectorVisible ? "Скрыть панель агента" : "Показать панель агента")
                    }
                }.padding(.leading, leadingInset).padding(.trailing, 18)
            }
            .padding(.top, 14)
            .frame(height: 64, alignment: .top)
        }
        .background {
            if presentation.isConversation {
                Color.clear.contentShape(Rectangle())
                    .gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { headerWidth = $0 }
    }

    private var profile: some View {
        HStack(spacing: 8) {
            if let group = presentation.group {
                MacTeamGroupAvatar(agents: presentation.members(of: group), size: 36)
            } else {
                MacTeamAvatar(agent: presentation.agent, size: 36)
            }
            Button(action: showProfile) {
                titleLabel.contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help(presentation.group == nil ? "Настройки агента" : "Настройки группы")
            .accessibilityLabel((presentation.group == nil ? "Настройки агента: " : "Настройки группы: ") + presentation.title)
        }
    }

    private var titleLabel: some View {
        Text(presentation.title).font(.system(size: 17, weight: .semibold))
            .lineLimit(1).contentTransition(.opacity)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(WorkspaceStyle.ink)
    }

    private func showProfile() {
        presentation.sheet = presentation.group.map { .group($0.id) } ?? .editAgent
    }
}
