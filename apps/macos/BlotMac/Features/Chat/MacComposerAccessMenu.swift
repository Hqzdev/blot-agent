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
        MacActionMenu(edge: .trailing, isSubmenu: true) {
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
            HStack {
                BlotLabel(store.t("Access mode"), symbol: "lock.shield", size: 17)
                Spacer(minLength: 4)
                if let current = modes.first(where: { $0.0 == selection }) {
                    Text(store.t(current.1)).font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
