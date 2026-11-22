import BlotDesign
import SwiftUI

struct MacChatStarters: View {
    let examples: [MacChatTaskExample]
    let russian: Bool
    @Binding var draft: String
    let focus: () -> Void
    @State private var selected: MacChatTaskTopic?
    @State private var inserted: String?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion

    private var selectionAnimation: Animation? {
        systemReduceMotion || reduceMotion ? nil : BlotInterfaceMotion.quick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                HStack(spacing: 6) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(MacChatTaskTopic.allCases, id: \.self) { topic in
                                Button { choose(topic) } label: {
                                    topicLabel(topic)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 10).frame(height: 29)
                                        .background(topic == selected ? BlotColor.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(BlotPlainButtonStyle()).kHover(radius: 8).id(topic)
                                .accessibilityAddTraits(selected == topic ? .isSelected : [])
                            }
                        }
                    }.scrollIndicators(.hidden)
                    MacActionMenu {
                        ForEach(MacChatTaskTopic.allCases, id: \.self) { topic in
                            Button {
                                withAnimation(selectionAnimation) {
                                    selected = topic
                                    proxy.scrollTo(topic, anchor: .center)
                                }
                            } label: { topicLabel(topic) }
                        }
                    } label: {
                        BlotIcon(.more, size: BlotIconSize.control).frame(width: 30, height: 29)
                    }.accessibilityLabel(russian ? "Все темы" : "All topics")
                }
            }
            if let selected {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { choices(selected) }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { choices(selected) }
                }.id(selected).transition(.opacity)
            }
        }
    }

    private func topicLabel(_ topic: MacChatTaskTopic) -> some View {
        HStack(spacing: 6) {
            BlotIcon(topic.glyph, size: BlotIconSize.inline)
            Text(topic.title(russian: russian))
        }
    }

    private func choose(_ topic: MacChatTaskTopic) {
        withAnimation(selectionAnimation) { selected = selected == topic ? nil : topic }
    }

    private func choices(_ topic: MacChatTaskTopic) -> some View {
        ForEach(topic.examples(russian: russian, personal: examples), id: \.title) { example in
            Button {
                draft = example.prompt
                inserted = example.prompt
                focus()
            } label: {
                HStack(spacing: 6) {
                    BlotIcon(.arrowUpLeft, size: BlotIconSize.inline)
                    Text(example.title).lineLimit(2)
                }.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 5)
            }.buttonStyle(BlotPlainButtonStyle()).kHover(radius: 8).help(example.prompt)
                .disabled(!draft.isEmpty && draft != inserted)
        }
    }
}
