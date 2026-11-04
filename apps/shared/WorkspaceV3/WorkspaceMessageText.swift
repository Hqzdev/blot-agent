import Foundation
import SwiftUI

struct WorkspaceMessageText: View {
    let text: String
    var markdown = true

    var body: some View {
        if markdown, let content = try? AttributedString(markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(content)
        } else { Text(text) }
    }
}
