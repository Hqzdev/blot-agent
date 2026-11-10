import SwiftUI

/// Product captions may arrive as Strings; user messages and document content stay verbatim.
struct WorkspaceLocalizedText: View {
    private let source: String
    @Environment(\.locale) private var locale

    init(_ source: String) { self.source = source }

    var body: some View {
        Text(verbatim: WorkspaceCopy.text(source, language: locale.language.languageCode?.identifier ?? "en"))
    }
}
