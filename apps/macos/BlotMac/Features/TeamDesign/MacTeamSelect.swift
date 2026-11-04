import BlotDesign
import SwiftUI

struct MacTeamOption<Value: Hashable> {
    let title: String
    let value: Value
    init(_ title: String, _ value: Value) {
        self.title = title
        self.value = value
    }
}

struct MacTeamSelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [MacTeamOption<Value>]
    var showsTitle = true
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 20) {
            if showsTitle {
                Text(title)
                Spacer(minLength: 8)
            }
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text(options.first { $0.value == selection }?.title ?? title).lineLimit(1)
                    BlotIcon(.chevronDown, size: BlotIconSize.inline).rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(WorkspaceStyle.ink)
                }.font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }.buttonStyle(BlotPlainButtonStyle())
                .kAnimation(KMotion.quick, value: expanded)
                .accessibilityLabel(title)
                .accessibilityValue(options.first { $0.value == selection }?.title ?? "")
                .popover(isPresented: $expanded, arrowEdge: .bottom) {
                    VStack(spacing: 3) {
                        ForEach(options, id: \.value) { option in
                            MacTeamNavigationButton(selected: selection == option.value) {
                                selection = option.value
                                expanded = false
                            } label: {
                                HStack(spacing: 24) {
                                    Text(option.title)
                                    Spacer(minLength: 8)
                                    BlotIcon(symbol: "checkmark", size: BlotIconSize.inline)
                                        .opacity(selection == option.value ? 1 : 0)
                                }.font(.system(size: 12))
                            }
                        }
                    }.padding(6).frame(minWidth: 200).background(MacTeamStyle.panel)
                }
        }
    }
}

extension MacTeamSelect where Value == String {
    init(title: String, selection: Binding<String>, values: [String], showsTitle: Bool = true) {
        self.title = title
        self._selection = selection
        self.options = values.map { MacTeamOption($0, $0) }
        self.showsTitle = showsTitle
    }
}
