import SwiftUI

struct BlotPressFeedback: ViewModifier {
    let pressed: Bool
    var scale: CGFloat = 0.98
    @Environment(\.blotReduceMotion) private var preference
    @Environment(\.accessibilityReduceMotion) private var system

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !(preference || system) ? scale : 1)
            .animation(preference || system ? nil : BlotInterfaceMotion.press, value: pressed)
    }
}

public struct BlotPlainButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    private let disabledOpacity: Double
    public init(disabledOpacity: Double = 0.4) { self.disabledOpacity = disabledOpacity }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : disabledOpacity)
            .modifier(BlotPressFeedback(pressed: enabled && configuration.isPressed, scale: 0.99))
    }
}
