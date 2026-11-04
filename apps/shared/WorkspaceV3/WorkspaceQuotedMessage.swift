import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceQuotedMessage: View {
    let message: BlotV3.Message
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(WorkspaceStyle.ink.opacity(0.35)).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.messageAuthor(message)).font(.caption.weight(.semibold)).lineLimit(1)
                Text(store.t(message.content)).font(.footnote).foregroundStyle(WorkspaceStyle.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}
