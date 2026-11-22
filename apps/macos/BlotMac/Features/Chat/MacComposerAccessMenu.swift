import BlotDesign
import BlotDomain
import SwiftUI

struct MacComposerAccessMenu: View {
    @Binding var selection: BlotV3.AccessMode
    @Environment(WorkspaceStore.self) private var store

    private let modes: [(BlotV3.AccessMode, String)] = [
        (.observe, "Observe"), (.ask_first, "Ask first"), (.trusted_scope, "Trusted scope")
    ]

    var body: some View {
        MacActionMenu(edge: .top) {
            ForEach(modes, id: \.0) { mode, title in
                Button { selection = mode } label: {
                    HStack {
                        Text(store.t(title))
                        Spacer()
                        if selection == mode { BlotIcon(.check, size: 14) }
                    }
                }.accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(store.t(modes.first { $0.0 == selection }?.1 ?? "Access mode"), systemImage: "lock.shield")
                    .font(.system(size: 12)).fixedSize()
                Image(systemName: "lock.shield")
            }.padding(.horizontal, 5).frame(minHeight: 26)
                .help(store.t("Access mode"))
        }
    }
}
