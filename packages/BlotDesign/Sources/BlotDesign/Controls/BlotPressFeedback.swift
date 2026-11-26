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
    private let hoverShape: AnyShape?

    public init(disabledOpacity: Double = 0.4, showsHover: Bool = true) {
        self.disabledOpacity = disabledOpacity
        hoverShape = showsHover ? AnyShape(RoundedRectangle(cornerRadius: 10)) : nil
    }

    public init(disabledOpacity: Double = 0.4, hoverIn shape: some Shape) {
        self.disabledOpacity = disabledOpacity
        hoverShape = AnyShape(shape)
    }

    @ViewBuilder public func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .blotHitArea()
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : disabledOpacity)
            .modifier(BlotPressFeedback(pressed: enabled && configuration.isPressed, scale: 0.99))
        #if os(macOS)
        if let hoverShape { label.blotHover(in: hoverShape) }
        else { label }
        #else
        label
        #endif
    }
}

public struct BlotSecondaryTextButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Button(configuration)
            .buttonStyle(BlotPlainButtonStyle(showsHover: false))
            .modifier(BlotSecondaryTextHover())
        #else
        Button(configuration)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        #endif
    }
}

public extension View {
    /// Tints an action within its existing outline without changing its layout or hit target.
    @ViewBuilder func blotHover(in shape: some Shape, color: Color = BlotColor.hover) -> some View {
        #if os(macOS)
        modifier(BlotHoverFeedback(shape: shape, color: color))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct BlotSecondaryTextHover: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.blotReduceMotion) private var preference
    @Environment(\.accessibilityReduceMotion) private var system
    @State private var hovering = false

    func body(content: Content) -> some View {
        let highlighted = enabled && hovering
        content
            .foregroundStyle(highlighted ? BlotColor.text : BlotColor.textSecondary)
            .animation(preference || system ? nil : BlotInterfaceMotion.quick, value: highlighted)
            .onHover { hovering = $0 }
    }
}

private struct BlotHoverFeedback<Outline: Shape>: ViewModifier {
    let shape: Outline
    let color: Color
    @Environment(\.isEnabled) private var enabled
    @Environment(\.blotReduceMotion) private var preference
    @Environment(\.accessibilityReduceMotion) private var system
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                shape.fill(color)
                    .opacity(enabled && hovering ? 1 : 0)
                    .animation(preference || system ? nil : BlotInterfaceMotion.quick, value: enabled && hovering)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onHover { hovering = $0 }
    }
}
#endif
