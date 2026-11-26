import BlotDesign
import SwiftUI

struct MacWorkspacePillButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(WorkspaceStyle.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(BlotColor.hairline))
                .blotHitArea()
        }
        .buttonStyle(BlotHitTargetButtonStyle(hoverIn: Capsule(), hoverColor: .clear))
        .macSidebarHoverTarget()
    }
}
