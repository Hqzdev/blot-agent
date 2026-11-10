import BlotAppleIntegrations

enum MacTeamSamples {
    static let plugins = PluginCatalog.all.map {
        MacTeamPlugin(id: $0.id, name: $0.name, assetName: $0.asset, category: $0.category, summary: $0.summary)
    }
}
