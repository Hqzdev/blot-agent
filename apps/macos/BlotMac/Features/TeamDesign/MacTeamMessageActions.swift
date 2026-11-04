import BlotDesign
import SwiftUI

enum MacTeamMessageAction: String, CaseIterable {
    case reply = "Ответить", copy = "Копировать", remember = "Запомнить"

    var symbol: String {
        switch self {
        case .reply: "arrowshape.turn.up.left"
        case .copy: "doc.on.doc"
        case .remember: "brain"
        }
    }

    @MainActor func perform(_ message: MacDemoMessage, in presentation: MacTeamPresentation) {
        switch self {
        case .reply: presentation.reply(to: message)
        case .copy: presentation.copy(message)
        case .remember: presentation.remember(message)
        }
    }
}

struct MacTeamMessageMenu: View {
    let message: MacDemoMessage
    let close: () -> Void
    @Environment(MacTeamPresentation.self) private var presentation

    var body: some View {
        MacTeamMessageMenuLayout(choices: MacDemoReaction.choices, react: { presentation.react($0, to: message) },
            selected: selected, perform: { $0.perform(message, in: presentation) }, close: close)
    }

    private func selected(_ emoji: String) -> Bool {
        message.reactions?.contains { $0.authorID == MacDemoReaction.userID && $0.emoji == emoji } == true
    }
}

/// Original message-menu presentation with commands supplied by the active data source.
struct MacTeamMessageMenuLayout: View {
    let choices: [String]
    let react: (String) -> Void
    let selected: (String) -> Bool
    let perform: (MacTeamMessageAction) -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.self) { emoji in
                Button {
                    react(emoji)
                    close()
                } label: {
                    Text(emoji).font(.system(size: 22)).frame(width: 39, height: 40)
                        .background(WorkspaceStyle.ink.opacity(selected(emoji) ? 0.1 : 0), in: Circle())
                }.buttonStyle(BlotPlainButtonStyle()).accessibilityLabel("Реакция " + emoji)
                    .accessibilityAddTraits(selected(emoji) ? [.isSelected] : [])
            }
        }.padding(.vertical, 3)
        Divider()
        ForEach(MacTeamMessageAction.allCases, id: \.self) { action in
            MacTeamNavigationButton {
                perform(action)
                close()
            } label: {
                BlotLabel(action.rawValue, symbol: action.symbol, size: BlotIconSize.control).font(.system(size: 12))
            }
        }
    }
}

struct MacTeamMessageReactions: View {
    let message: MacDemoMessage
    @Environment(MacTeamPresentation.self) private var presentation

    var body: some View {
        HStack(spacing: 5) {
            ForEach(MacDemoReaction.choices, id: \.self) { emoji in
                let reactions = (message.reactions ?? []).filter { $0.emoji == emoji }
                if !reactions.isEmpty {
                    let mine = reactions.contains { $0.authorID == MacDemoReaction.userID }
                    Button { presentation.react(emoji, to: message) } label: {
                        HStack(spacing: 4) {
                            Text(emoji).font(.system(size: 14))
                            Text("\(reactions.count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        }.padding(.horizontal, 8).padding(.vertical, 5)
                            .background(WorkspaceStyle.ink.opacity(mine ? 0.12 : 0.045), in: Capsule())
                            .overlay(Capsule().strokeBorder(WorkspaceStyle.ink.opacity(mine ? 0.35 : 0.08)))
                    }.buttonStyle(BlotPlainButtonStyle())
                        .accessibilityLabel("Реакция \(emoji), \(reactions.count)")
                        .accessibilityAddTraits(mine ? [.isSelected] : [])
                        .help(reactions.map { $0.authorID == MacDemoReaction.userID ? "Вы" : presentation.agent(for: $0.authorID).name }.joined(separator: ", "))
                }
            }
        }.kAnimation(KMotion.standard, value: message.reactions)
    }
}
