import BlotDesign
import SwiftUI

struct NavigationRail: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 8) {
            RailButton(icon: .home, title: "Home", selected: !app.showingSettings && app.isNewConversation) {
                app.openSection(.chats)
            }
            sectionButton(.scheduled, icon: "clock")
            sectionButton(.skills, icon: "puzzlepiece.extension")
            WorkspaceMoreMenu()
                .modifier(RailTooltip(title: "More"))
            HDivider().padding(.horizontal, 12).padding(.vertical, 4)
            if app.product == .code { sectionButton(.motes, icon: "person.2").transition(.opacity) }
            Spacer()
            RailButton(icon: .symbol("gearshape"), title: "Settings · ⌘,", selected: app.showingSettings) {
                app.openProfileSettings(app.settings.section)
            }
            ProfileMenuButton().modifier(RailTooltip(title: "Profile"))
        }
        .padding(.vertical, 8).frame(width: K.railWidth).frame(maxHeight: .infinity)
        .background(K.bgChrome)
    }

    private func sectionButton(_ section: ShellSection, icon: String) -> some View {
        RailButton(icon: .symbol(icon), title: section.rawValue,
                   selected: app.activeTool == nil && !app.profileVisible && !app.showingSettings && app.shellSection == section) {
            app.openSection(section)
        }
    }
}

private struct RailButton: View {
    let icon: RailIcon
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            icon.image(color: selected ? K.text : K.text2)
                .frame(width: K.railButtonSize, height: K.railButtonSize).kHover(radius: K.rMd, active: selected)
        }.buttonStyle(KIconButtonStyle()).kFocusRing()
            .modifier(RailTooltip(title: title))
            .accessibilityLabel(title.kSpokenTitle)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RailTooltip: ViewModifier {
    let title: String
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active: hovered = true
                case .ended: hovered = false
                }
            }
            .overlay(alignment: .leading) {
                if hovered {
                    Text(title).font(KFont.ui(13)).foregroundStyle(K.text)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .kPopover(radius: K.rMd)
                        .fixedSize().offset(x: 42).allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .zIndex(hovered ? 1 : 0)
    }
}
