import BlotDesign
import SwiftUI

/// Forms share Blot's surfaces and spacing while retaining native text editing and accessibility.
struct WorkspacePanelForm<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.workspacePanelNavigation) private var panel
    var body: some View {
        if panel != nil {
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
        } else { Form { content }.formStyle(.grouped) }
    }
}

extension View {
    @ViewBuilder func workspacePanelControls() -> some View {
        #if os(macOS)
        self.teamControls()
        #else
        self.buttonStyle(WorkspaceButtonStyle(.secondary)).tint(WorkspaceStyle.ink)
        #endif
    }
}

struct WorkspacePanelTextFieldStyle: TextFieldStyle {
    @Environment(\.workspacePanelNavigation) private var panel
    @ViewBuilder func _body(configuration: TextField<Self._Label>) -> some View {
        #if os(macOS)
        if panel != nil { configuration.textFieldStyle(MacTeamTextFieldStyle()) }
        else { configuration.textFieldStyle(.roundedBorder) }
        #else
        configuration.textFieldStyle(.roundedBorder)
        #endif
    }
}

struct WorkspacePanelToggleStyle: ToggleStyle {
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(MacTeamSwitchStyle())
        #else
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        #endif
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
    @State private var expanded = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    Text(options.first { $0.value == selection }?.title ?? "—").multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(WorkspaceStyle.secondary)
                }.padding(12).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BlotColor.edge))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).opacity(enabled ? 1 : 0.45)
                .accessibilityLabel(title).accessibilityValue(options.first { $0.value == selection }?.title ?? "—")
                .popover(isPresented: $expanded, arrowEdge: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(options) { option in
                                Button { selection = option.value; expanded = false } label: {
                                    HStack(spacing: 12) {
                                        Text(option.title).multilineTextAlignment(.leading)
                                        Spacer(minLength: 12)
                                        Image(systemName: "checkmark").opacity(option.value == selection ? 1 : 0)
                                    }.font(.system(size: 13)).padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(option.value == selection ? WorkspaceStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                                        .contentShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityAddTraits(option.value == selection ? [.isSelected] : [])
                            }
                        }.padding(8)
                    }.frame(idealWidth: 280, maxHeight: 320).background(WorkspaceStyle.canvas).presentationCompactAdaptation(.popover)
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
            Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "minus") }.disabled(value <= range.lowerBound).accessibilityLabel("−\(step)")
            Text(value.formatted()).monospacedDigit().frame(minWidth: 24)
            Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "plus") }.disabled(value >= range.upperBound).accessibilityLabel("+\(step)")
        }.workspacePanelControls()
    }
}
