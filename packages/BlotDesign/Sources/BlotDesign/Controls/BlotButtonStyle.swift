//
//  BlotButtonStyle.swift
//  BlotDesign
//
//  Neutral controls. Every state is told apart by fill and outline, never by hue:
//  hover adds a 5 % veil, press a 10 % veil, focus a 2 pt ink ring, disabled greys the label
//  and drops the fill.
//

import SwiftUI

nonisolated public enum BlotButtonKind: Sendable, Equatable {
    /// Panel fill with a hairline border — the default action.
    case secondary
    /// Ink fill with paper label — the one main action on a screen (send, sign in).
    case primary
    /// No fill until hovered — toolbars and inline actions.
    case ghost
    /// Bordered like `secondary`, semibold label; pair it with a trash or warning icon and a
    /// clear verb, because colour is not used.
    case destructive
    /// Bordered capsule — reserved for the sign-in entry.
    case pill
}

nonisolated public enum BlotControlSize: Sendable, Equatable {
    case compact, regular, large

    public var height: CGFloat {
        switch self {
        case .compact: 28
        case .regular: BlotLayout.controlHeight
        case .large: BlotLayout.controlHeightLarge
        }
    }
}

public struct BlotButtonStyle: ButtonStyle {
    public var kind: BlotButtonKind
    public var size: BlotControlSize
    public var fullWidth: Bool

    public init(_ kind: BlotButtonKind = .secondary, size: BlotControlSize = .regular, fullWidth: Bool = false) {
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        BlotButtonBody(label: configuration.label, pressed: configuration.isPressed,
                       kind: kind, size: size, fullWidth: fullWidth)
    }
}

private struct BlotButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    let label: Label
    let pressed: Bool
    let kind: BlotButtonKind
    let size: BlotControlSize
    let fullWidth: Bool

    var body: some View {
        label
            .font(BlotFont.role(.caption, weight: kind == .destructive ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .compact ? BlotSpace.s8 : BlotSpace.s12)
            .frame(minHeight: size.height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background { shape.fill(fill) }
            .overlay { shape.fill(veil) }
            .overlay { shape.strokeBorder(border, lineWidth: BlotLayout.hairlineWidth) }
            .contentShape(shape)
            .onHover { hovering = $0 }
    }

    /// The pill uses an oversized radius, which SwiftUI clamps to a capsule.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: kind == .pill ? 999 : BlotRadius.control, style: .continuous)
    }

    private var foreground: Color {
        guard enabled else { return BlotColor.textTertiary }
        return kind == .primary ? BlotColor.onInverse : BlotColor.text
    }

    private var fill: Color {
        switch kind {
        case .primary: enabled ? BlotColor.inverse : BlotColor.fill
        case .ghost: .clear
        case .secondary, .destructive, .pill: BlotColor.panel
        }
    }

    /// Hover and press veils sit on top of the fill so they also work on the ink button.
    private var veil: Color {
        guard enabled else { return .clear }
        if kind == .primary {
            return pressed ? BlotColor.canvas.opacity(0.24) : hovering ? BlotColor.canvas.opacity(0.12) : .clear
        }
        return pressed ? BlotColor.pressed : hovering ? BlotColor.hover : .clear
    }

    private var border: Color {
        switch kind {
        case .primary, .ghost: .clear
        case .secondary, .destructive, .pill:
            enabled && (hovering || pressed) ? BlotColor.hairlineStrong : BlotColor.hairline
        }
    }
}

/// Square icon button: transparent until hovered, grey fill when selected.
public struct BlotIconButtonStyle: ButtonStyle {
    public var size: CGFloat
    public var selected: Bool

    public init(size: CGFloat = BlotLayout.iconButton, selected: Bool = false) {
        self.size = size
        self.selected = selected
    }

    public func makeBody(configuration: Configuration) -> some View {
        BlotIconButtonBody(label: configuration.label, pressed: configuration.isPressed,
                           size: size, selected: selected)
    }
}

private struct BlotIconButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    let label: Label
    let pressed: Bool
    let size: CGFloat
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous)
        label
            .foregroundStyle(enabled ? (selected ? BlotColor.text : BlotColor.textSecondary) : BlotColor.textTertiary)
            .frame(width: size, height: size)
            .background(shape.fill(fill))
            .contentShape(shape)
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        guard enabled else { return .clear }
        if pressed { return BlotColor.pressed }
        if selected { return BlotColor.selected }
        return hovering ? BlotColor.hover : .clear
    }
}

/// Ink send button with an arrow. Shows a spinner while sending and a retry arrow after a failure.
public struct BlotSendButton: View {
    nonisolated public enum Phase: Sendable, Equatable { case ready, sending, retry }

    private let phase: Phase
    private let size: CGFloat
    private let action: () -> Void

    public init(phase: Phase = .ready, size: CGFloat = BlotLayout.iconButton, action: @escaping () -> Void) {
        self.phase = phase
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                switch phase {
                case .sending: ProgressView().controlSize(.small).tint(BlotColor.onInverse)
                case .retry: Image(systemName: "arrow.clockwise").font(.system(size: size * 0.46, weight: .semibold))
                case .ready: Image(systemName: "arrow.up").font(.system(size: size * 0.5, weight: .semibold))
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(BlotSendButtonStyle())
        .disabled(phase == .sending)
        .accessibilityLabel(phase == .sending ? "Sending" : phase == .retry ? "Retry sending" : "Send message")
    }
}

private struct BlotSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BlotSendButtonBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct BlotSendButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var enabled
    let label: Label
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BlotRadius.control, style: .continuous)
        label
            .foregroundStyle(enabled ? BlotColor.onInverse : BlotColor.textTertiary)
            .background(shape.fill(enabled ? BlotColor.inverse : BlotColor.fill))
            .overlay(shape.fill(pressed && enabled ? BlotColor.canvas.opacity(0.24) : .clear))
            .contentShape(shape)
    }
}
