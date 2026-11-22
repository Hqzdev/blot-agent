import BlotDesign
import BlotWorkspace
import SwiftUI

enum MacComposerModelPreferences {
    static let tierKey = "blot.mac.composer.model"
    static let effortKey = "blot.mac.composer.effort"

    static var profile: BlotInferenceProfile? {
        guard let raw = UserDefaults.standard.string(forKey: tierKey), let tier = BlotModelTier(rawValue: raw) else { return nil }
        let effort = UserDefaults.standard.string(forKey: effortKey).flatMap(BlotModelEffort.init(rawValue:)) ?? .medium
        return .init(tier: tier, effort: effort)
    }
}

struct MacComposerModelMenu: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage(MacComposerModelPreferences.tierKey) private var rawTier = ""
    @AppStorage(MacComposerModelPreferences.effortKey) private var effort = BlotModelEffort.medium

    private var tier: BlotModelTier? { BlotModelTier(rawValue: rawTier) }
    private var automatic: String { store.language == "ru" ? "Модель агента" : "Agent model" }

    var body: some View {
        HStack(spacing: 4) {
            MacActionMenu(edge: .top) {
                ForEach(BlotModelTier.allCases, id: \.self) { item in
                    Button { rawTier = item.rawValue } label: { option(item.title, checked: tier == item) }
                }
                WorkspaceMenuGap()
                Button { rawTier = "" } label: { option(automatic, checked: tier == nil) }
            } label: { chip(tier?.title ?? automatic) }
            if let tier, tier != .mini {
                MacActionMenu(edge: .top) {
                    ForEach(BlotModelEffort.allCases, id: \.self) { item in
                        Button { effort = item } label: { option(item.rawValue.capitalized, checked: item == effort) }
                    }
                } label: { chip(effort.rawValue.capitalized).foregroundStyle(.secondary) }
            }
        }
    }

    private func chip(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            BlotIcon(.chevronDown, size: 10)
        }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 6).frame(minHeight: 26)
    }

    private func option(_ title: String, checked: Bool) -> some View {
        HStack { Text(title); Spacer(); if checked { BlotIcon(.check, size: 13) } }
            .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
