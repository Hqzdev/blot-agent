import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct PhonePinnedMessagesBar: View {
    let message: BlotV3.Message
    let index: Int
    let count: Int
    let select: () -> Void
    let showList: () -> Void
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 10) {
                    BlotIcon(.pin, size: 17).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(store.groupPlan(for: message) == nil ? store.t("Pinned message") : (store.language == "ru" ? "План работы" : "Work plan")).font(.caption.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("\(index + 1) / \(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(preview)
                            .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("Go to pinned message") + ": " + preview)
            Button(action: showList) {
                BlotIcon(symbol: "list.bullet", size: 18).frame(width: 44, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(store.t("All pinned messages"))
        }
        .foregroundStyle(WorkspaceStyle.ink)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .accessibilityIdentifier("workspace.chat.pinned-messages")
    }
    private var preview: String {
        guard let plan = store.groupPlan(for: message) else { return message.content.isEmpty ? store.t("Attachment") : String(message.content.prefix(240)) }
        return "\(plan.completedCount)/\(plan.steps.count) · " + (plan.steps.first { !$0.completed }?.task ?? (store.language == "ru" ? "Все пункты выполнены" : "All steps completed"))
    }
}

struct PhonePinnedMessagesList: View {
    let select: (UUID) -> Void
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.currentPinnedMessages.reversed(), id: \.metadata.id) { message in
                    Button {
                        dismiss()
                        select(message.metadata.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            if let plan = store.groupPlan(for: message) {
                                WorkspaceGroupPlanCard(plan: plan, agents: store.snapshot.agents,
                                    skills: store.snapshot.skills ?? [], russian: store.language == "ru")
                            } else {
                                HStack {
                                    BlotIcon(.pin, size: 13)
                                    Text(author(of: message)).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(message.metadata.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(message.content.isEmpty ? store.t("Attachment") : message.content)
                                    .font(.body).lineLimit(3).multilineTextAlignment(.leading)
                            }
                        }.padding(.vertical, 5).foregroundStyle(WorkspaceStyle.ink)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { store.toggleMessagePin(message.metadata.id) } label: {
                            Label(store.t("Unpin message"), systemImage: "pin.slash")
                        }.disabled(store.pendingMessagePins.contains(message.metadata.id))
                    }
                }
            }
            .overlay {
                if store.currentPinnedMessages.isEmpty {
                    ContentUnavailableView(store.t("No pinned messages"), systemImage: "pin.slash")
                }
            }
            .navigationTitle(store.t("Pinned messages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func author(of message: BlotV3.Message) -> String {
        if message.role == .user { return store.t("You") }
        return store.snapshot.agents.first { $0.metadata.id == message.authorAgentId }?.name ?? "Blot"
    }
}
