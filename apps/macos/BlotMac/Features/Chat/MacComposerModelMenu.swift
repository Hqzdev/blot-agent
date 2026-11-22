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
                    Button { rawTier = item.rawValue } label: { option(item.title, glyph: item.menuGlyph, checked: tier == item) }
                }
                WorkspaceMenuGap()
                Button { rawTier = "" } label: { option(automatic, glyph: .agent, checked: tier == nil) }
            } label: { chip(tier?.title ?? automatic, color: BlotColor.textSecondary) }
            if let tier, tier != .mini {
                MacActionMenu(edge: .top) {
                    ForEach(BlotModelEffort.allCases, id: \.self) { item in
                        Button { effort = item } label: { option(item.rawValue.capitalized, glyph: item.menuGlyph, checked: item == effort) }
                    }
                } label: { chip(effort.rawValue.capitalized, color: .secondary) }
            }
        }
    }

    private func chip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .regular).width(.condensed))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minHeight: 26)
    }

    private func option(_ title: String, glyph: BlotGlyph, checked: Bool) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                BlotIcon(glyph, size: BlotIconSize.control)
            }
            Spacer(minLength: 8)
            if checked { BlotIcon(.check, size: BlotIconSize.inline) }
        }.accessibilityAddTraits(checked ? .isSelected : [])
    }
}

private extension BlotModelTier {
    var menuGlyph: BlotGlyph {
        switch self {
        case .mini: .bolt
        case .pro: .chip
        case .max: .memory
        }
    }
}

private extension BlotModelEffort {
    var menuGlyph: BlotGlyph {
        switch self {
        case .light: .bolt
        case .medium: .sliders
        case .high: .usage
        case .extra: .gauge
        }
    }
}
