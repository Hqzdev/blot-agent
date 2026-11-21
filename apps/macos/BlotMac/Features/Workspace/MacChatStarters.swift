import BlotDesign
import SwiftUI

struct MacChatStarters: View {
    let russian: Bool
    let select: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { choices }
            VStack(alignment: .leading, spacing: 4) { choices }
        }
    }

    @ViewBuilder private var choices: some View {
        choice("doc.text", russian ? "Документ" : "Document",
               russian ? "Помоги составить документ. Тема: " : "Help me draft a document. Topic: ")
        choice("list.bullet", russian ? "План" : "Plan",
               russian ? "Разбей задачу на этапы. Моя цель: " : "Break this task into steps. My goal: ")
        choice("text.alignleft", russian ? "Редактура" : "Edit text",
               russian ? "Помоги отредактировать текст:\n" : "Help me edit this text:\n")
    }

    private func choice(_ symbol: String, _ title: String, _ prompt: String) -> some View {
        Button { select(prompt) } label: {
            HStack(spacing: 6) {
                BlotIcon(symbol: symbol, size: 13).accessibilityHidden(true)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).frame(minHeight: 30)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain).help(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
