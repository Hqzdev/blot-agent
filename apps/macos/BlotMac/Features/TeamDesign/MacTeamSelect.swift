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
    @Environment(\.locale) private var locale
    var body: some View {
        WorkspaceChoice(title: localized(title), selection: $selection,
            options: options.map { .init($0.value, localized($0.title)) }, showsTitle: showsTitle)
            .frame(minWidth: 140, idealWidth: 220, maxWidth: 300)
    }
    private func localized(_ text: String) -> String {
        WorkspaceCopy.text(text, language: locale.language.languageCode?.identifier ?? "en")
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
