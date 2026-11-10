import BlotDomain
import BlotAppleIntegrations
import BlotWorkspace
import SwiftUI

/// Attribution comes from durable calls/results, including calls preceding a separate final reply.
struct WorkspaceMessagePlugins: View {
    let message: BlotV3.Message
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let plugins = store.chatContent.plugins(for: message)
        if !plugins.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { labels(plugins) }
                VStack(alignment: .leading, spacing: 6) { labels(plugins) }
            }.font(.caption).accessibilityIdentifier("workspace.chat.plugins")
        }
    }
    @ViewBuilder private func labels(_ plugins: [WorkspacePluginReference]) -> some View {
        ForEach(plugins) { plugin in
            HStack(spacing: 5) {
                WorkspacePluginLogo(plugin: plugin, size: 16)
                Text("@" + plugin.name).foregroundStyle(plugin.color).fontWeight(.semibold)
            }.accessibilityElement(children: .combine)
        }
    }
}
