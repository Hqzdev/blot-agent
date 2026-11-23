import BlotDomain
import SwiftUI

/// The query follows the insertion point, so completing a mention keeps the rest of the message.
struct MacComposerSkillQuery {
    let range: Range<String.Index>
    let text: String

    init?(draft: String, selection: TextSelection?) {
        let caret: String.Index
        switch selection?.indices {
        case .selection(let range) where range.isEmpty && range.lowerBound <= draft.endIndex:
            caret = range.lowerBound
        case nil: caret = draft.endIndex
        default: return nil
        }
        let prefix = draft[..<caret]
        guard let at = prefix.lastIndex(of: "@"),
              at == draft.startIndex || draft[draft.index(before: at)].isWhitespace else { return nil }
        let query = prefix[prefix.index(after: at)...]
        guard !query.contains(where: \.isWhitespace) else { return nil }
        let end = draft[caret...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.endIndex
        range = at..<end
        text = String(query)
    }
}

struct MacComposerSkillSuggestions: View {
    let matches: [BlotV3.Skill]
    let russian: Bool
    let select: (String) -> Void
    let manage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if matches.isEmpty {
                Text(russian ? "Подходящих скиллов нет" : "No matching skills")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 9)
                Button(action: manage) {
                    Label(russian ? "Открыть скиллы" : "Open skills", systemImage: "shippingbox")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(matches, id: \.metadata.id) { skill in
                            Button { select(skill.name) } label: { Label(skill.name, systemImage: "shippingbox") }
                        }
                    }
                }.frame(height: CGFloat(min(4, matches.count)) * 30)
            }
        }.buttonStyle(MacMenuRowStyle()).padding(6)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}
