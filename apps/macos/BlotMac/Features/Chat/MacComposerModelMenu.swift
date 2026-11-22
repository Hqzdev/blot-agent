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

    private let extraInk = BlotColor.dynamic(.init(light: 0x62399DFF, dark: 0xD5BEFFFF))
    private let extraFill = BlotColor.dynamic(.init(light: 0xEFE7FAFF, dark: 0x402D57FF))

    var body: some View {
        HStack(spacing: 4) {
            MacActionMenu(edge: .top) {
                ForEach(BlotModelTier.allCases, id: \.self) { item in
                    Button { rawTier = item.rawValue } label: { option(item.title, glyph: item.menuGlyph, checked: tier == item) }
                }
                WorkspaceMenuGap()
                Button { rawTier = "" } label: { option(automatic, glyph: .agent, checked: tier == nil) }
            } label: { chip(tier?.title ?? automatic) }
            if let tier, tier != .mini {
                MacActionMenu(edge: .top) {
                    ForEach(BlotModelEffort.allCases, id: \.self) { item in
                        Button { effort = item } label: { option(item.rawValue.capitalized, glyph: item.menuGlyph, checked: item == effort, accented: item == .extra && item == effort) }
                    }
                } label: { chip(effort.rawValue.capitalized, highlighted: effort == .extra) }
            }
        }
    }

    private func chip(_ title: String, highlighted: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 13, weight: highlighted ? .medium : .regular))
            .foregroundStyle(highlighted ? extraInk : BlotColor.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(highlighted ? extraFill : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func option(_ title: String, glyph: BlotGlyph, checked: Bool, accented: Bool = false) -> some View {
        HStack {
            Label {
                Text(title)
                    .foregroundStyle(accented ? extraInk : BlotColor.text)
            } icon: {
                BlotIcon(glyph, size: BlotIconSize.control)
                    .foregroundStyle(accented ? extraInk : BlotColor.text)
            }
            Spacer(minLength: 8)
            if checked {
                BlotIcon(.check, size: BlotIconSize.inline)
                    .foregroundStyle(accented ? extraInk : BlotColor.text)
            }
        }
        .frame(minHeight: 25)
        .background(accented ? extraFill : .clear, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

private extension BlotModelTier {
    var menuGlyph: BlotGlyph {
        switch self {
        case .mini: .skill
        case .pro: .chip
        case .max: .sparkle
        }
    }
}

private extension BlotModelEffort {
    var menuGlyph: BlotGlyph {
        switch self {
        case .light: .circle
        case .medium: .progress
        case .high: .gauge
        case .extra: .bolt
        }
    }
}
