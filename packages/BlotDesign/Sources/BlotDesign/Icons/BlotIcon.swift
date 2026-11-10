import SwiftUI

public enum BlotIconSize {
    public static let inline: CGFloat = 14
    public static let control: CGFloat = 18
    public static let navigation: CGFloat = 20
    public static let prominent: CGFloat = 24
    public static let illustration: CGFloat = 28
}

public struct BlotIcon: View {
    private let glyph: BlotGlyph
    private let size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    public init(_ glyph: BlotGlyph, size: CGFloat = 20) {
        self.glyph = glyph
        self.size = size
    }

    public init(symbol: String, size: CGFloat = 20) {
        self.glyph = BlotGlyph(symbol: symbol)
        self.size = size
    }

    public var body: some View {
        Image(glyph.assetName, bundle: .module).renderingMode(.template)
            .resizable().scaledToFit().frame(width: size * scale, height: size * scale)
            .accessibilityHidden(true)
    }
}

public struct BlotLabel: View {
    private let title: String
    private let symbol: String
    private let size: CGFloat

    public init(_ title: String, symbol: String, size: CGFloat = 20) {
        self.title = title; self.symbol = symbol; self.size = size
    }

    public var body: some View {
        Label { Text(LocalizedStringKey(title)) } icon: { BlotIcon(symbol: symbol, size: size) }
    }
}

public struct BlotIconButton: View {
    private let title: String
    private let symbol: String
    private let action: () -> Void
    private let size: CGFloat

    public init(_ title: String, symbol: String, size: CGFloat = BlotIconSize.navigation, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.size = size; self.action = action
    }

    public var body: some View {
        Button(action: action) { BlotLabel(title, symbol: symbol, size: size) }
    }
}
