import BlotDesign
import SwiftUI

struct PhoneFirstAgentAppearancePicker: View {
    @Binding var draft: WorkspaceAgentForm
    let localize: (String) -> String

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text(localize("Shape")).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(PhoneAgentAppearance.shapes, id: \.self) { shape in
                        Button { draft.shape = shape.rawValue } label: {
                            WorkspaceAvatar(shape: shape, color: WorkspaceAvatarView.color(draft.color), size: 36, showsEyes: false)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(WorkspaceStyle.secondary.opacity(draft.shape == shape.rawValue ? 0.12 : 0.04),
                                    in: .rect(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(draft.shape == shape.rawValue ? WorkspaceStyle.secondary : .clear) }
                        }.buttonStyle(.plain).accessibilityLabel(localize(shape.rawValue))
                            .accessibilityAddTraits(draft.shape == shape.rawValue ? .isSelected : [])
                    }
                }
            }
            VStack(spacing: 12) {
                Text(localize("Color")).font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 12) {
                    ForEach(PhoneAgentAppearance.colors, id: \.self) { color in
                        Button { draft.color = color } label: {
                            Circle().fill(WorkspaceAvatarView.color(color)).frame(width: 28, height: 28)
                                .overlay { Circle().strokeBorder(WorkspaceStyle.secondary.opacity(0.15)) }
                                .frame(width: 44, height: 44)
                                .overlay { Circle().strokeBorder(draft.color == color ? WorkspaceStyle.ink : .clear, lineWidth: 2) }
                        }.buttonStyle(.plain).accessibilityLabel(localize(color))
                            .accessibilityAddTraits(draft.color == color ? .isSelected : [])
                    }
                }
            }
        }
    }
}
