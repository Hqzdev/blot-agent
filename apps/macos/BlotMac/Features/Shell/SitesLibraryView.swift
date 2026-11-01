import BlotDesign
import SwiftUI

struct SitesLibraryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var adding = false
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: KSpace.xl) {
                PageHeader(title: "Sites", subtitle: "Keep useful websites close to your work.") {
                    KButton(title: "Add site", icon: "plus") { adding = true }
                }
                if app.workspaceLibrary.sites.isEmpty {
                    EmptyState(icon: WorkspaceTool.sites.icon, title: "No saved sites",
                                       detail: "Add a website to open it from your workspace.")
                } else {
                    SettingsGroup(title: "Saved sites") {
                        ForEach(Array(app.workspaceLibrary.sites.enumerated()), id: \.element.id) { index, site in
                            if index > 0 { SettingsDivider() }
                            ListRow(title: site.name, subtitle: site.url.host ?? site.url.absoluteString,
                                    action: { openURL(site.url) }) {
                                IconTile(icon: "globe")
                            } trailing: {
                                IconButton(icon: "square-arrow-out-up-right", help: "Open \(site.name)") { openURL(site.url) }
                                IconButton(icon: "trash-2", help: "Remove \(site.name)") { app.workspaceLibrary.removeSite(site.id) }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { SiteEditorView { app.workspaceLibrary.saveSite($0) } }
    }
}

private struct SiteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let save: (SavedSite) -> Void
    @State private var name = ""
    @State private var address = ""
    private var url: URL? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let url = URL(string: value.contains("://") ? value : "https://" + value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    var body: some View {
        KSheet("Add site", subtitle: "Saved on this Mac and shown in Sites and on your profile showcase.", width: 460) {
            KTextField("Website URL", text: $address, placeholder: "example.com", mono: true, required: true,
                       error: !address.isEmpty && url == nil ? "Enter a valid http or https address without credentials." : nil,
                       autofocus: true)
            KTextField("Name", text: $name, placeholder: "Optional", hint: "Leave empty to use the site's address.")
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            KButton(title: "Add site", kind: .primary) {
                guard let url else { return }
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                save(SavedSite(id: UUID(), name: title.isEmpty ? url.host ?? address : title, url: url))
                dismiss()
            }.disabled(url == nil).keyboardShortcut(.defaultAction)
        }
    }
}
