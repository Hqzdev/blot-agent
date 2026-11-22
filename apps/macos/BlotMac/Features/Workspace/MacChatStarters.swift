import SwiftUI

struct MacChatStarters: View {
    let examples: [MacChatTaskExample]
    let russian: Bool
    @Binding var draft: String
    let focus: () -> Void
    @State private var selected: MacChatTaskTopic?
    @State private var inserted: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                HStack(spacing: 6) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(MacChatTaskTopic.allCases, id: \.self) { topic in
                                Button { choose(topic) } label: {
                                    Label(topic.title(russian: russian), systemImage: topic.symbol)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 10).frame(height: 29)
                                        .background(.primary.opacity(topic == selected ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain).id(topic)
                                .accessibilityAddTraits(selected == topic ? .isSelected : [])
                            }
                        }
                    }.scrollIndicators(.hidden)
                    MacActionMenu {
                        ForEach(MacChatTaskTopic.allCases, id: \.self) { topic in
                            Button {
                                selected = topic
                                proxy.scrollTo(topic, anchor: .center)
                            } label: { Label(topic.title(russian: russian), systemImage: topic.symbol) }
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 30, height: 29)
                    }.accessibilityLabel(russian ? "Все темы" : "All topics")
                }
            }
            if let selected {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { choices(selected) }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { choices(selected) }
                }
            }
        }
    }

    private func choose(_ topic: MacChatTaskTopic) {
        selected = selected == topic ? nil : topic
    }

    private func choices(_ topic: MacChatTaskTopic) -> some View {
        ForEach(topic.examples(russian: russian, personal: examples), id: \.title) { example in
            Button {
                draft = example.prompt
                inserted = example.prompt
                focus()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left")
                    Text(example.title).lineLimit(2)
                }.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 5)
            }.buttonStyle(.borderless).help(example.prompt)
                .disabled(!draft.isEmpty && draft != inserted)
        }
    }
}
