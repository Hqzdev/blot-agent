import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceGroupAgentRow: View {
    let agent: BlotV3.AgentProfile
    let selected: Bool
    let toggle: () -> Void
    @Environment(WorkspaceStore.self) private var store
    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                WorkspaceAvatarView(agent: agent, size: 44)
                    .frame(width: 52, height: 52)
                    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(agent.name).font(.body.weight(.medium)).lineLimit(1)
                    Text(agent.instructions).font(.caption).foregroundStyle(WorkspaceStyle.secondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(selected ? WorkspaceStyle.ink : WorkspaceStyle.secondary.opacity(0.4))
            }.padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(WorkspaceStyle.ink.opacity(selected ? 0.065 : hovered ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WorkspaceStyle.ink.opacity(selected ? 0.18 : 0.07)))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .kAnimation(KMotion.quick, value: selected)
            .accessibilityElement(children: .ignore).accessibilityLabel(agent.name)
            .accessibilityValue(store.t(selected ? "Selected" : "Not selected"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
