import BlotDesign
import SwiftUI

struct MacChatStarters: View {
    let examples: [MacChatTaskExample]
    let select: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { choices }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) { choices }
        }
    }

    private var choices: some View {
        ForEach(examples, id: \.title) { example in
            Button { select(example.prompt) } label: {
                Text(example.title)
                    .lineLimit(2)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).help(example.prompt)
        }
    }
}
