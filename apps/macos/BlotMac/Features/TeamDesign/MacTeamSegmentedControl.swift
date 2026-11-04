import BlotDesign
import SwiftUI

struct MacTeamSegmentedControl: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    @Namespace private var indicator
    @State private var hoveredTab: String?
    private let inset: CGFloat = 3

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { tab in
                let selected = selection == tab
                Button {
                    selection = tab
                } label: {
                    Text(tab)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? BlotColor.onInverse : WorkspaceStyle.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous)
                                    .fill(BlotColor.inverse)
                                    .matchedGeometryEffect(id: "selection", in: indicator)
                            } else if hoveredTab == tab {
                                RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous)
                                    .fill(WorkspaceStyle.ink.opacity(0.05))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous))
                }
                .buttonStyle(BlotPlainButtonStyle())
                .onHover { hovering in hoveredTab = hovering ? tab : nil }
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(inset)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: BlotRadius.control + inset, style: .continuous))
        .kAnimation(KMotion.standard, value: selection)
        .kAnimation(KMotion.quick, value: hoveredTab)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
