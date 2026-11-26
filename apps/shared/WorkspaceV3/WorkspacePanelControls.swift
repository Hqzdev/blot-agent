import BlotDesign
import SwiftUI

/// Forms share Ori's surfaces and spacing while retaining native text editing and accessibility.
struct WorkspacePanelForm<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Group(sections: content) { sections in
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            section.header.font(.system(size: 12, weight: .semibold)).foregroundStyle(WorkspaceStyle.secondary)
                            VStack(alignment: .leading, spacing: 16) { section.content }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                            section.footer.font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                        }
                    }
                }
            }.padding(20)
        }.background(WorkspaceStyle.canvas).workspacePanelControls()
    }
}

extension View {
    func workspacePanelControls() -> some View {
        self.buttonStyle(WorkspaceButtonStyle(.secondary))
            .textFieldStyle(BlotTextFieldStyle()).toggleStyle(BlotToggleStyle())
            .disclosureGroupStyle(BlotDisclosureStyle()).progressViewStyle(BlotProgressStyle())
            .tint(WorkspaceStyle.ink).environment(\.blotChatChrome, false)
    }
}

struct WorkspacePanelTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(BlotTextFieldStyle())
    }
}

struct WorkspacePanelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(BlotToggleStyle())
    }
}

struct WorkspaceChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
    init(_ value: Value, _ title: String) { self.value = value; self.title = title }
}

/// A product-styled choice list; the full selected value remains readable in a narrow pane.
struct WorkspaceChoice<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [WorkspaceChoiceOption<Value>]
    var showsTitle = true
    @State private var expanded = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsTitle { Text(title).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Text(options.first { $0.value == selection }?.title ?? "—").multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    BlotIcon(.chevronsUpDown, size: 16).foregroundStyle(WorkspaceStyle.secondary)
                }.padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BlotColor.edge))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(BlotPlainButtonStyle()).blotFocusRing(radius: 16).opacity(enabled ? 1 : 0.45)
                .accessibilityLabel(title).accessibilityValue(options.first { $0.value == selection }?.title ?? "—")
                .popover(isPresented: $expanded, arrowEdge: .bottom) {
                    #if os(macOS)
                    MacActionMenuPanel {
                        ForEach(options) { option in
                            Button { selection = option.value; expanded = false } label: {
                                HStack {
                                    Text(option.title)
                                    Spacer()
                                    if option.value == selection { BlotIcon(.check, size: 14) }
                                }
                            }.buttonStyle(MacMenuRowStyle()).accessibilityAddTraits(option.value == selection ? .isSelected : [])
                        }
                    }
                    #else
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(options) { option in
                                Button { selection = option.value; expanded = false } label: {
                                    HStack(spacing: 12) {
                                        Text(option.title).multilineTextAlignment(.leading)
                                        Spacer(minLength: 12)
                                        BlotIcon(.check, size: 16).opacity(option.value == selection ? 1 : 0)
                                    }.font(.system(size: 13)).padding(12).frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(option.value == selection ? WorkspaceStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                                        .contentShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(BlotPlainButtonStyle()).blotFocusRing().accessibilityAddTraits(option.value == selection ? [.isSelected] : [])
                            }
                        }.padding(8)
                    }.frame(idealWidth: 280, maxHeight: 320).background(WorkspaceStyle.canvas).presentationBackground(WorkspaceStyle.canvas).presentationCornerRadius(22).presentationCompactAdaptation(.popover)
                    #endif
                }
        }
    }
}

struct WorkspaceCounter: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var body: some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Button { value = max(range.lowerBound, value - step) } label: { BlotIcon(symbol: "minus", size: 16) }.disabled(value <= range.lowerBound).accessibilityLabel("−\(step)")
            Text(value.formatted()).monospacedDigit().frame(minWidth: 24)
            Button { value = min(range.upperBound, value + step) } label: { BlotIcon(.plus, size: 16) }.disabled(value >= range.upperBound).accessibilityLabel("+\(step)")
        }.workspacePanelControls()
    }
}
