import BlotDesign
import SwiftUI

struct PhoneGlassCircleButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BlotIcon(symbol: symbol, size: 22).font(.system(size: 21, weight: .regular))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct PhoneGlassCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content.padding(.horizontal, 12).frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

enum PhoneReferenceStyle {
    static var authentication: Color { BlotColor.dynamic(.init(light: 0xF7F7F5FF, dark: 0x191919FF)) }
    static var field: Color { BlotColor.dynamic(.init(light: 0xF1F1EFFF, dark: 0x242424FF)) }
    static var provider: Color { BlotColor.dynamic(.init(light: 0xEAE8E6FF, dark: 0x303030FF)) }
}
