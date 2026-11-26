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
        MacActionMenuPanel(width: 280) {
            if page == .account {
                accountMenu
            } else {
                row(store.t("Back"), glyph: .chevronLeft) { page = .account }
                WorkspaceMenuGap()
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
        .task { await store.refreshBilling() }
        .onChange(of: page) { linkFailed = false }
        .confirmationDialog(ru ? "Выйти из Ori на этом Mac?" : "Sign out of Ori on this Mac?",
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
            row(ru ? "Расход за неделю" : "Weekly usage", glyph: .gauge,
                value: weeklyPercent.map { "\($0)%" }, accessory: .chevronRight) { page = .usage }
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

        row(ru ? "Ori для iPhone" : "Ori for iPhone", glyph: .mobile, accessory: .arrowUpRight) {
            visit(URL(string: "https://blot-agent.vercel.app/beta?platform=ios")!)
        }
        row(ru ? "Поддержка" : "Support", glyph: .question, accessory: .chevronRight) {
            page = .support
        }
        row(store.t("Settings"), glyph: .settings) {
            close()
            store.navigate(.settings)
        }
        WorkspaceMenuGap()
        row(ru ? "Создать аккаунт на сайте" : "Create account on the web", glyph: .personAdd, accessory: .arrowUpRight) {
            visit(URL(string: "https://blot-agent.vercel.app/register")!)
        }
        row(store.t("Sign out"), glyph: .logout) {
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
        row(ru ? "Статистика использования" : "Usage statistics", glyph: .usage) {
            close()
            store.navigate(.usage)
        }
    }

    @ViewBuilder private var supportLinks: some View {
        row(ru ? "Документация Ori" : "Ori documentation", glyph: .book, accessory: .arrowUpRight) {
            visit(URL(string: "https://blot-agent.vercel.app/docs")!)
        }
        row(ru ? "Связаться с поддержкой" : "Contact support", glyph: .chat, accessory: .arrowUpRight) {
            visit(URL(string: "https://blot-agent.vercel.app/contact")!)
        }
    }

    private func visit(_ url: URL) {
        openURL(url) { opened in
            if opened { close() } else { linkFailed = true }
        }
    }

    private func row(_ title: String, glyph: BlotGlyph, value: String? = nil, accessory: BlotGlyph? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                BlotIcon(glyph, size: BlotIconSize.control).frame(width: 18)
                Text(title)
                Spacer(minLength: 4)
                if let value { Text(value).monospacedDigit() }
                if let accessory {
                    BlotIcon(accessory, size: BlotIconSize.inline).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(MacMenuRowStyle())
    }
}
