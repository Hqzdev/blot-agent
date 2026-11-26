import SwiftUI

/// Visual roles measured from the November screen set. Navigation belongs to each app.
public enum WorkspaceStyle {
    #if os(macOS)
    public static var canvas: Color { BlotColor.dynamic(.init(light: 0xFDFDFDFF, dark: 0x101010FF)) }
    public static var surface: Color { BlotColor.dynamic(.init(light: 0xEEEEEEFF, dark: 0x1F1F1FFF)) }
    public static let radius: CGFloat = 22
    public static let contentWidth: CGFloat = 880
    #else
    public static var canvas: Color { BlotColor.dynamic(.init(light: 0xFFFFFFFF, dark: 0x111111FF)) }
    public static var surface: Color { BlotColor.dynamic(.init(light: 0xF3F3F3FF, dark: 0x222222FF)) }
    public static let radius: CGFloat = 26
    public static let contentWidth: CGFloat = 1120
    #endif
    public static var ink: Color { BlotColor.text }
    public static var secondary: Color { BlotColor.textSecondary }
}

public struct WorkspaceButtonStyle: PrimitiveButtonStyle {
    public enum Kind { case primary, secondary, quiet, destructive }
    let kind: Kind
    public init(_ kind: Kind = .primary) { self.kind = kind }
    @ViewBuilder public func makeBody(configuration: Configuration) -> some View {
        switch kind {
        case .primary:
            Button(configuration).buttonStyle(BlotButtonStyle(.primary, size: .large))
                .modifier(BlotButtonHitHalo(expansion: 3, action: configuration.trigger))
        case .secondary:
            Button(configuration).buttonStyle(BlotButtonStyle(.secondary, size: .large))
                .modifier(BlotButtonHitHalo(expansion: 3, action: configuration.trigger))
        case .destructive:
            Button(configuration).buttonStyle(BlotButtonStyle(.destructive, size: .large))
                .modifier(BlotButtonHitHalo(expansion: 3, action: configuration.trigger))
        case .quiet:
            Button(configuration).buttonStyle(BlotPlainButtonStyle())
        }
    }
}

/// Flat content actions; floating navigation and input controls own their glass treatment.
public struct WorkspaceRowButtonStyle: ButtonStyle {
    private let padding: CGFloat
    @Environment(\.isEnabled) private var enabled
    public init(padding: CGFloat = 12) { self.padding = padding }
    public func makeBody(configuration: Configuration) -> some View {
        #if os(iOS)
        configuration.label
            .padding(.horizontal, padding).padding(.vertical, padding == 0 ? 0 : 4)
            .frame(minHeight: 44)
            .foregroundStyle(configuration.role == .destructive ? Color.red : WorkspaceStyle.ink)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .modifier(BlotPressFeedback(pressed: enabled && configuration.isPressed, scale: 0.99))
        #else
        configuration.label
            .blotHitArea()
            .blotHover(in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .modifier(BlotPressFeedback(pressed: enabled && configuration.isPressed, scale: 0.99))
        #endif
    }
}

public extension View {
    func workspaceGlassContainer() -> some View {
        GlassEffectContainer(spacing: 8) { self }
    }

    func workspaceInputSurface(cornerRadius: CGFloat = 20) -> some View {
        blotPanel(fill: BlotColor.panel, radius: max(cornerRadius, 16))
    }
}
