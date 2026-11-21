import BlotDesign
import BlotWorkspace
import SwiftUI

struct MacSidebarProfileMenu: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var page = Page.account
    @State private var confirmingSignOut = false
    @State private var linkFailed = false

    let close: () -> Void

    private enum Page { case account, usage, support }

    private var ru: Bool { store.language == "ru" }
    private var weeklyPercent: Int? {
        store.billingOverview?.usage?.windows.first { $0.hours == 7 * 24 }?.percent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if page == .account {
                accountMenu
            } else {
                row(store.t("Back"), symbol: "chevron.backward") { page = .account }
                Divider()
                switch page {
                case .usage: usageDetails
                case .support: supportLinks
                case .account: EmptyView()
                }
            }
            if linkFailed {
                Text(ru ? "Не удалось открыть ссылку." : "Could not open the link.")
                    .font(.caption).padding(.horizontal, 8)
            }
        }
        .padding(10)
        .frame(width: 294, alignment: .leading)
        .foregroundStyle(WorkspaceStyle.ink)
        .presentationBackground(WorkspaceStyle.canvas)
        .task { await store.refreshBilling() }
        .onChange(of: page) { linkFailed = false }
        .confirmationDialog(ru ? "Выйти из Blot на этом Mac?" : "Sign out of Blot on this Mac?",
                            isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button(store.t("Sign out"), role: .destructive) {
                close()
                store.signOut()
            }
            Button(store.t("Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder private var accountMenu: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.accountDisplayName).font(.headline).lineLimit(2)
            if !store.form.account.email.isEmpty && store.form.account.email != store.accountDisplayName {
                Text(store.form.account.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)

        VStack(alignment: .leading, spacing: 4) {
            row(ru ? "Расход за неделю" : "Weekly usage", symbol: "gauge.with.dots.needle.50percent",
                value: weeklyPercent.map { "\($0)%" }, accessory: "chevron.forward") { page = .usage }
            if let weeklyPercent {
                ProgressView(value: Double(weeklyPercent), total: 100)
                    .progressViewStyle(.linear).accessibilityHidden(true)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
            WorkspaceBillingView(showsLimits: false)
                .padding(.horizontal, 8)
        }
        .padding(6)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 4)

        row(ru ? "Blot для iPhone" : "Blot for iPhone", symbol: "iphone", accessory: "arrow.up.right") {
            visit(URL(string: "https://blot-agent.vercel.app/beta?platform=ios")!)
        }
        row(ru ? "Поддержка" : "Support", symbol: "questionmark.circle", accessory: "chevron.forward") {
            page = .support
        }
        row(store.t("Settings"), symbol: "gearshape") {
            close()
            store.navigate(.settings)
        }
        Divider().padding(.vertical, 3)
        row(ru ? "Создать аккаунт на сайте" : "Create account on the web", symbol: "person.badge.plus", accessory: "arrow.up.right") {
            visit(URL(string: "https://blot-agent.vercel.app/register")!)
        }
        row(store.t("Sign out"), symbol: "rectangle.portrait.and.arrow.right") {
            confirmingSignOut = true
        }.disabled(store.busy)
    }

    @ViewBuilder private var usageDetails: some View {
        if let usage = store.billingOverview?.usage {
            WorkspaceUsageLimitsView(usage: usage, ru: ru)
                .padding(10)
        } else {
            Text(ru ? "Нет данных о лимитах" : "No usage data available")
                .font(.callout).foregroundStyle(.secondary).padding(10)
        }
        WorkspaceBillingView(showsLimits: false).padding(.horizontal, 8)
        row(ru ? "Статистика использования" : "Usage statistics", symbol: "chart.bar") {
            close()
            store.navigate(.usage)
        }
    }

    @ViewBuilder private var supportLinks: some View {
        row(ru ? "Документация Blot" : "Blot documentation", symbol: "book", accessory: "arrow.up.right") {
            visit(URL(string: "https://blot-agent.vercel.app/docs")!)
        }
        row(ru ? "Связаться с поддержкой" : "Contact support", symbol: "bubble.left", accessory: "arrow.up.right") {
            visit(URL(string: "https://blot-agent.vercel.app/contact")!)
        }
    }

    private func visit(_ url: URL) {
        openURL(url) { opened in
            if opened { close() } else { linkFailed = true }
        }
    }

    private func row(_ title: String, symbol: String, value: String? = nil, accessory: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 18).accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 4)
                if let value { Text(value).monospacedDigit() }
                if let accessory {
                    Image(systemName: accessory).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9).frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceRowButtonStyle())
    }
}
