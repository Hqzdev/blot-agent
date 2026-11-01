import BlotDesign
import Foundation

struct AccountPlugin: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let launchURL: URL
    var usageCount: Int = 0
}

/// Installation membership comes from the signed-in account, never the usage cache.
final class AccountPluginUsage {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func mostUsed(for user: AuthUser?) -> [AccountPlugin] {
        guard let user else { return [] }
        let counts = counts(for: user.email)
        return user.installedPlugins.sorted { lhs, rhs in
            let left = lhs.usageCount + (counts[lhs.id] ?? 0)
            let right = rhs.usageCount + (counts[rhs.id] ?? 0)
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func recordOpening(_ pluginID: String, for user: AuthUser) {
        guard user.installedPlugins.contains(where: { $0.id == pluginID }) else { return }
        var counts = counts(for: user.email)
        counts[pluginID, default: 0] += 1
        defaults.set(counts, forKey: key(for: user.email))
    }

    private func counts(for account: String) -> [String: Int] {
        defaults.dictionary(forKey: key(for: account)) as? [String: Int] ?? [:]
    }

    private func key(for account: String) -> String { "blot.plugins.usage." + account.lowercased() }
}
