import BlotAppleIntegrations
import BlotWorkspace
import Foundation
import SwiftUI

/// One catalog identity supplies both inline mentions and recorded tool-use labels.
struct WorkspacePluginReference: Identifiable {
    let entry: PluginCatalogEntry
    let name: String
    var id: String { entry.id + ":" + name }
    var color: Color {
        switch entry.id {
        case "apple.mail", "apple.files", "drive", "composio", "atlassian", "1password": .blue
        case "apple.calendar", "calendar", "gmail", "adobe": .red
        case "apple.reminders", "apple.shortcuts", "slack", "loom": .purple
        case "apple.notes": .yellow
        case "apple.contacts", "beehiiv": .orange
        case "quickbooks", "freshdesk", "granola": .green
        case "zapier": .orange
        case "airtable", "asana": .pink
        default: .primary
        }
    }
    static let all: [Self] = PluginCatalog.all.flatMap { entry in
        let aliases: [String]
        switch entry.appleID {
        case .mail: aliases = ["Mail", "Email", "Apple Mail"]
        case .calendar: aliases = ["Calendar", "Apple Calendar"]
        case .reminders: aliases = ["Reminders", "Apple Reminders"]
        case .notes: aliases = ["Notes", "Apple Notes"]
        case .contacts: aliases = ["Contacts", "Apple Contacts"]
        case .files: aliases = ["Finder", "Files", "Файлы"]
        case .shortcuts: aliases = ["Shortcuts", "Apple Shortcuts"]
        case nil: aliases = []
        }
        return Array(Set([entry.name] + aliases)).sorted().map { Self(entry: entry, name: $0) }
    }
    static func plugin(forTool name: String) -> Self? {
        guard let plugin = AppleToolCatalog.all.first(where: { $0.definition.name == name })?.plugin,
              let entry = PluginCatalog.apple.first(where: { $0.appleID == plugin }) else { return nil }
        return Self(entry: entry, name: entry.name)
    }
    static func mentionedIDs(in text: String) -> Set<String> {
        let content = WorkspaceMarkdownCache.content(text)
        let plain = String(content.characters)
        let targets = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        guard let references = try? WorkspaceNamedReferences.find(plain, names: targets.mapValues(\.name)) else { return [] }
        return Set(references.compactMap { reference in
            guard let range = Range(NSRange(location: reference.startUTF16, length: reference.lengthUTF16), in: plain),
                  plain[range.lowerBound] == "@", let target = targets[reference.id] else { return nil }
            let start = content.characters.index(content.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: range.lowerBound))
            let end = content.characters.index(start, offsetBy: plain.distance(from: range.lowerBound, to: range.upperBound))
            guard !content[start..<end].runs.contains(where: { $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true }) else { return nil }
            return target.entry.id
        })
    }
}

struct WorkspacePluginLogo: View {
    let plugin: WorkspacePluginReference
    let size: CGFloat
    var body: some View {
        Group {
            if let appleID = plugin.entry.appleID { ApplePluginIcon(plugin: appleID, size: size) }
            else { Image(plugin.entry.asset).resizable().scaledToFit().frame(width: size, height: size) }
        }.accessibilityHidden(true)
    }
}
