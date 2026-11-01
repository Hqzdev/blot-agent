import BlotDesign
import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let save: (ProfileDetails) -> Void
    @State private var name: String
    @State private var username: String
    @State private var bio: String

    init(details: ProfileDetails, save: @escaping (ProfileDetails) -> Void) {
        self.save = save
        _name = State(initialValue: details.name)
        _username = State(initialValue: details.username)
        _bio = State(initialValue: details.bio)
    }

    private var details: ProfileDetails {
        ProfileDetails(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                       username: username.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@")),
                       bio: bio.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        KSheet("Edit profile", subtitle: "Changes are saved on this Mac.", width: 480) {
            KTextField("Name", text: $name, required: true, autofocus: true)
            KTextField("Username", text: $username, icon: "at", mono: true,
                       error: username.isEmpty || details.isValid || details.name.isEmpty ? nil : "Use letters, numbers and underscores, up to 32 characters.",
                       hint: "Letters, numbers and underscores. Up to 32 characters.")
            KTextArea("Bio", text: $bio, placeholder: "A line about you", minHeight: 96, maxHeight: 160)
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            KButton(title: "Save", kind: .primary) { save(details); dismiss() }
                .disabled(!details.isValid).keyboardShortcut(.defaultAction)
        }
    }
}

struct ProfileShowcaseEditor: View {
    @Environment(\.dismiss) private var dismiss
    let sites: [SavedSite]
    let save: (Set<UUID>) -> Void
    @State private var selected: Set<UUID>

    init(sites: [SavedSite], selected: Set<UUID>, save: @escaping (Set<UUID>) -> Void) {
        self.sites = sites
        self.save = save
        _selected = State(initialValue: selected)
    }

    var body: some View {
        KSheet("Edit showcase", subtitle: "Choose the sites to feature on your profile.", width: 480) {
            if sites.isEmpty {
                EmptyState(icon: "globe", title: "No saved sites",
                           detail: "Save a website in Sites from the More menu in the rail, then feature it here.")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                            if index > 0 { SettingsDivider() }
                            ListRow(title: site.name, subtitle: site.url.host ?? site.url.absoluteString) {
                                IconTile(icon: "globe")
                            } trailing: {
                                KToggle(isOn: Binding(get: { selected.contains(site.id) }, set: { enabled in
                                    if enabled { selected.insert(site.id) } else { selected.remove(site.id) }
                                })).accessibilityLabel("Feature \(site.name)")
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .kCard()
            }
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            if !sites.isEmpty {
                KButton(title: "Save", kind: .primary) { save(selected); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
