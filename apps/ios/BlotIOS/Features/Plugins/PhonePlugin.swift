import BlotAppleIntegrations
import Foundation

struct PhonePlugin: Identifiable {
    enum Section: String, CaseIterable { case apple = "Приложения Apple", featured = "Featured", team = "Team plugins" }
    let id: String
    let name: String
    let description: String
    let asset: String
    let section: Section
    let scopes: [String]
    var appleID: ApplePluginID? { ApplePluginID(rawValue: id) }
    static let all = PluginCatalog.all.map { entry in
        Self(id: entry.id, name: entry.name, description: entry.summary, asset: entry.asset,
            section: entry.appleID != nil ? .apple : ["gmail", "calendar", "drive", "granola"].contains(entry.id) ? .featured : .team,
            scopes: entry.scopes)
    }
}
