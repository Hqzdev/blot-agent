import BlotDesign
import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceBrowserManualControl: View {
    let controller: WorkspaceBrowserController
    @Environment(WorkspaceStore.self) private var store
    @State private var submitting = false
    private var pending: BlotV3.ConversationCard? {
        store.snapshot.cards?.first {
            guard $0.kind == "takeover", $0.state == "pending", $0.executorDeviceId == store.snapshot.localDeviceID,
                  $0.expiresAt.map({ $0 > Date() }) ?? true,
                  case .takeover(let takeover) = try? JSONDecoder().decode(WorkspaceCardContent.self, from: Data($0.payloadJSON.utf8)) else { return false }
            return takeover.tabID == controller.selectedID
        }
    }
    var body: some View {
        if let pending {
            VStack(alignment: .leading, spacing: 8) {
                BlotLabel(store.language == "ru" ? "Вы управляете браузером" : "You're in control", symbol: "hand.raised").font(.caption.weight(.medium))
                HStack(spacing: 16) {
                    Button(store.language == "ru" ? "Я закончил" : "I'm done") { respond(pending, action: "done") }
                    Button(store.language == "ru" ? "Пропустить" : "Skip") { respond(pending, action: "skip") }
                }.font(.callout).disabled(submitting)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
        }
    }
    private func respond(_ card: BlotV3.ConversationCard, action: String) {
        guard !submitting, let commands = store.cardCommands else { return }
        submitting = true
        _Concurrency.Task { @MainActor in
            defer { submitting = false }
            do {
                try await commands.respondToCard(card.metadata.id, version: card.metadata.version, response: .init(action: action))
                #if os(iOS)
                if store.route == .browser { controller.presented = false; store.back() }
                #endif
            }
            catch { controller.error = store.language == "ru" ? "Не удалось вернуть управление. Повторите." : "Couldn't return control. Try again." }
        }
    }
}
