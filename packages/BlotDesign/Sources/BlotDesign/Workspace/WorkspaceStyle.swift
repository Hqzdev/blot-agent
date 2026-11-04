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
    public func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(WorkspaceSolidButtonStyle(kind: kind))
    }
}

private struct WorkspaceSolidButtonStyle: ButtonStyle {
    let kind: WorkspaceButtonStyle.Kind
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: 30)
            .foregroundStyle(foreground).tint(foreground)
            .background(kind == .primary ? BlotColor.inverse : kind == .quiet ? .clear : WorkspaceStyle.surface,
                        in: RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous).strokeBorder(kind == .destructive ? Color.red.opacity(0.3) : .clear))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous))
            .modifier(BlotPressFeedback(pressed: enabled && configuration.isPressed))
        #else
        configuration.label
            .font(.system(.body, weight: .medium))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(minHeight: 44)
            .foregroundStyle(foreground)
            .tint(foreground)
            .background(kind == .primary ? BlotColor.inverse : kind == .quiet ? .clear : WorkspaceStyle.surface,
                        in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .destructive ? Color.red : .clear))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Capsule())
            .modifier(BlotPressFeedback(pressed: enabled && configuration.isPressed))
        #endif
    }
    private var foreground: Color {
        kind == .primary ? BlotColor.onInverse : kind == .destructive ? .red : WorkspaceStyle.ink
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
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .modifier(BlotPressFeedback(pressed: enabled && configuration.isPressed, scale: 0.99))
        #endif
    }
}

public extension View {
    func workspaceGlassContainer() -> some View {
        #if os(iOS)
        GlassEffectContainer(spacing: 8) { self }
        #else
        self
        #endif
    }

    func workspaceInputSurface(cornerRadius: CGFloat = 16) -> some View {
        let radius = max(cornerRadius, 20)
        #if os(iOS)
        return glassEffect(.regular.interactive(), in: .rect(cornerRadius: radius))
        #else
        return background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(BlotColor.edge))
        #endif
    }
}
