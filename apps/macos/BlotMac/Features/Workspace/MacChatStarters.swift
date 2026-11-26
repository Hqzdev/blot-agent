import BlotDesign
import SwiftUI

struct MacChatStarters: View {
    let examples: [MacChatTaskExample]
    let russian: Bool
    @Binding var draft: String
    let focus: () -> Void
    @State private var selected: MacChatTaskTopic?
    @State private var hoveredTopic: MacChatTaskTopic?
    @State private var inserted: String?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion

    private var motionEnabled: Bool { !systemReduceMotion && !reduceMotion }
    private var selectionAnimation: Animation? { motionEnabled ? BlotInterfaceMotion.standard : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                HStack(spacing: 6) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(MacChatTaskTopic.allCases, id: \.self) { topic in
                                topicButton(topic)
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
                            } label: {
                                topicLabel(topic)
                            }.accessibilityAddTraits(selected == topic ? .isSelected : [])
                        }
                    } label: {
                        BlotIcon(.more, size: BlotIconSize.control).frame(width: 30, height: 34)
                    }.accessibilityLabel(russian ? "Все темы" : "All topics")
                        .macHoverTip(russian ? "Все темы" : "All topics")
                }
            }
            if let selected {
                ViewThatFits(in: .vertical) {
                    exampleRows(for: selected).fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        exampleRows(for: selected)
                    }
                }.id(selected)
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: MacStarterReveal(progress: 0),
                            identity: MacStarterReveal(progress: 1)
                        ),
                        removal: .opacity
                    ))
            }
        }
    }

    private func exampleRows(for topic: MacChatTaskTopic) -> some View {
        VStack(spacing: 2) {
            ForEach(topic.examples(russian: russian, personal: examples), id: \.title) { example in
                exampleButton(example, topic: topic)
            }
        }
    }

    private func topicButton(_ topic: MacChatTaskTopic) -> some View {
        let active = selected == topic
        let hovered = hoveredTopic == topic
        let colors = topic.colors
        let shape = RoundedRectangle(cornerRadius: 10)
        return Button {
            withAnimation(selectionAnimation) { selected = active ? nil : topic }
        } label: {
            topicLabel(topic)
                .font(.system(size: 13, weight: active ? .medium : .regular))
                .foregroundStyle(active || hovered ? colors.ink : BlotColor.textSecondary)
                .padding(.horizontal, 10).frame(height: 34)
                .background(colors.tint.opacity(active ? 0.26 : hovered ? 0.15 : 0), in: shape)
                .overlay { shape.strokeBorder(active || hovered ? colors.tint.opacity(active ? 0.72 : 0.52) : BlotColor.hairline) }
                .animation(motionEnabled ? BlotInterfaceMotion.quick : nil, value: hovered)
        }
        .buttonStyle(BlotPlainButtonStyle(showsHover: false))
        .onHover { inside in
            if inside { hoveredTopic = topic }
            else if hoveredTopic == topic { hoveredTopic = nil }
        }
        .id(topic)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func topicLabel(_ topic: MacChatTaskTopic) -> some View {
        Label {
            Text(topic.title(russian: russian))
        } icon: {
            BlotIcon(topic.glyph, size: BlotIconSize.inline)
        }
    }

    private func exampleButton(_ example: MacChatTaskExample, topic: MacChatTaskTopic) -> some View {
        Button {
            draft = example.prompt
            inserted = example.prompt
            focus()
        } label: {
            HStack(spacing: 10) {
                BlotIcon(example.glyph, size: BlotIconSize.control)
                    .foregroundStyle(topic.colors.ink)
                    .frame(width: 28, height: 28)
                    .background(topic.colors.tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BlotColor.text)
                    Text(example.prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(BlotColor.textSecondary)
                }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                BlotIcon(.chevronRight, size: BlotIconSize.inline)
                    .foregroundStyle(BlotColor.textSecondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
        .buttonStyle(BlotPlainButtonStyle(hoverIn: RoundedRectangle(cornerRadius: 8)))
        .accessibilityLabel(example.title)
        .macHoverTip(example.prompt)
        .disabled(!draft.isEmpty && draft != inserted)
    }
}

private struct MacStarterReveal: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: (progress - 1) * 2 * BlotInterfaceMotion.shift)
            .mask(alignment: .top) {
                Rectangle().scaleEffect(x: 1, y: progress, anchor: .top)
            }
    }
}
