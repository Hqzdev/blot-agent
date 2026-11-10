import BlotAppleIntegrations
import Foundation

struct PhonePlugin: Identifiable {
    let id: String
    let name: String
    let description: String
    let asset: String
    let category: String
    let scopes: [String]
    var appleID: ApplePluginID? { ApplePluginID(rawValue: id) }
    static let all = (PluginCatalog.external + PluginCatalog.apple).map { entry in
        Self(id: entry.id, name: entry.name, description: entry.summary, asset: entry.asset,
            category: entry.category,
            scopes: entry.scopes)
    }
}
