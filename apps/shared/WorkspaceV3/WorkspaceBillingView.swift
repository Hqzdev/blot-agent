import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor protocol WorkspaceBillingProviding { func billingClient() -> WorkspaceBillingClient }
extension WorkspaceAccountApplicationService: WorkspaceBillingProviding {}

struct WorkspaceBillingView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var opening = false
    var showsLimits = true
    var cardID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsLimits, let usage = store.billingOverview?.usage {
                WorkspaceUsageLimitsView(usage: usage, ru: store.language == "ru")
            }
            if store.billingOverview != nil || store.mode == .preview {
                Button {
                    guard !opening, let commands = store.billingCommands else { return }
                    let owner = store.snapshot.ownerID
                    opening = true
                    _Concurrency.Task {
                        defer { opening = false }
                        do {
                            let url = try await commands.billingClient().startCheckout(cardID: cardID)
                            guard owner == store.snapshot.ownerID else { return }
                            #if os(macOS)
                            let opened = NSWorkspace.shared.open(url)
                            #else
                            let opened = PhoneLinkBrowser.open(url)
                            #endif
                            if !opened { store.error = store.language == "ru" ? "Не удалось открыть сайт оплаты." : "Could not open checkout." }
                        } catch { store.error = WorkspaceFailureCopy.message(error) }
                    }
                } label: {
                    Text(verbatim: store.billingOverview?.hasSubscription == true ? "Change" : "Upgrade")
                }.buttonStyle(WorkspaceButtonStyle(.primary)).disabled(opening || store.billingCommands == nil)
            } else if store.billingLoadFailed {
                Button {
                    _Concurrency.Task { await store.refreshBilling() }
                } label: {
                    Label {
                        Text(store.language == "ru" ? "Повторить загрузку подписки" : "Retry loading subscription")
                    } icon: {
                        BlotIcon(.refresh, size: BlotIconSize.control)
                    }
                }
            } else if store.billingCommands != nil {
                ProgressView().controlSize(.small)
            }
        }
    }
}

struct WorkspaceUsageLimitsView: View {
    let usage: WorkspaceBillingOverview.Usage
    let ru: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ru ? "Лимиты" : "Usage limits").font(.headline)
            Text((usage.test ? (ru ? "Тестовый тариф · " : "Test plan · ") : "") + usage.plan.capitalized)
            ForEach(usage.windows, id: \.hours) { window in
                HStack {
                    Text(window.hours == 5 ? (ru ? "За 5 часов" : "5 hours") : (ru ? "За 7 дней" : "7 days"))
                    Spacer()
                    Text("\(window.percent)%").monospacedDigit()
                }
                ProgressView(value: Double(window.percent), total: 100).tint(.primary)
                if let reset = window.resetsAt, let date = try? Date(reset, strategy: .iso8601.time(includingFractionalSeconds: true)) {
                    HStack { Text(ru ? "Сброс" : "Resets"); Text(date, style: .relative); Text(date, style: .time) }.font(.caption)
                } else {
                    Text(ru ? "Начнётся при первом использовании" : "Starts on first use").font(.caption)
                }
            }
        }
    }
}
