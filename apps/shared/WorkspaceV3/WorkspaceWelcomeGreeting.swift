import Foundation
import SwiftUI

/// Selects one greeting per presentation; ordinary state updates never reshuffle the text.
struct WorkspaceWelcomeGreeting: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var variant = Int.random(in: 0..<4)

    private var name: String {
        #if os(iOS)
        let nickname = store.profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }
        #endif
        return store.form.account.name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    private var title: AttributedString {
        let phrases = store.language == "ru"
            ? ["Что сделаем вместе", "Над чем поработаем", "С чего начнём", "Какая задача на сегодня"]
            : ["What shall we do together", "What shall we work on", "Where shall we start", "What's the plan for today"]
        var result = AttributedString(phrases[variant])
        if !name.isEmpty {
            result.append(AttributedString(", "))
            var personal = AttributedString(name)
            personal.underlineStyle = .single
            result.append(personal)
        }
        result.append(AttributedString("?"))
        return result
    }

    var body: some View {
        Text(title).accessibilityAddTraits(.isHeader)
    }
}
