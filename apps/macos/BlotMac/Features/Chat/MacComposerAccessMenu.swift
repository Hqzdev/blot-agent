import BlotDesign
import BlotDomain
import SwiftUI

struct MacComposerAccessMenu: View {
    @Binding var selection: BlotV3.AccessMode
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        MacActionMenu(edge: .top) {
            ForEach(BlotV3.AccessMode.allCases, id: \.self) { mode in
                Button { selection = mode } label: {
                    HStack {
                        Label {
                            Text(store.t(mode.menuTitle))
                        } icon: {
                            BlotIcon(mode.menuGlyph, size: BlotIconSize.control)
                        }
                        Spacer(minLength: 8)
                        if selection == mode { BlotIcon(.check, size: BlotIconSize.inline) }
                    }
                }.accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    BlotIcon(selection.menuGlyph, size: BlotIconSize.inline)
                    Text(store.t(selection.menuTitle))
                }.font(.system(size: 12)).fixedSize()
                BlotIcon(selection.menuGlyph, size: BlotIconSize.inline)
            }.padding(.horizontal, 5).frame(minHeight: 26)
                .accessibilityLabel(store.t(selection.menuTitle))
                .help(store.t("Access mode"))
        }
    }
}

private extension BlotV3.AccessMode {
    var menuTitle: String {
        switch self {
        case .observe: "Observe"
        case .ask_first: "Ask first"
        case .trusted_scope: "Trusted scope"
        }
    }

    var menuGlyph: BlotGlyph {
        switch self {
        case .observe: .eye
        case .ask_first: .question
        case .trusted_scope: .shieldCheck
        }
    }
}
