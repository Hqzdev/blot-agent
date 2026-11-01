//
//  BlotSurfaces.swift
//  BlotDesign
//
//  Flat surfaces. Elevation is a 1 pt hairline, never a shadow, blur or glass.
//

import SwiftUI

public extension View {
    /// Panel, card, menu or popover: filled shape with a hairline border and 10 pt corners.
    func blotPanel(fill: Color = BlotColor.panel, radius: CGFloat = BlotRadius.panel,
                   border: Color = BlotColor.hairline) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: BlotLayout.hairlineWidth))
            .clipShape(shape)
    }

    /// Navigation or list row: clear by default, veil on hover, grey when selected.
    func blotRow(selected: Bool = false, radius: CGFloat = BlotRadius.control) -> some View {
        modifier(BlotRowBackground(selected: selected, radius: radius))
    }

    /// 2 pt ink ring while the view has keyboard focus.
    func blotFocusRing(radius: CGFloat = BlotRadius.control) -> some View {
        modifier(BlotFocusRing(radius: radius))
    }

    /// 1 pt separator along one edge.
    func blotHairline(_ edge: Edge, color: Color = BlotColor.hairline) -> some View {
        overlay(alignment: edge.blotAlignment) {
            Rectangle()
                .fill(color)
                .frame(width: edge == .leading || edge == .trailing ? BlotLayout.hairlineWidth : nil,
                       height: edge == .top || edge == .bottom ? BlotLayout.hairlineWidth : nil)
                .allowsHitTesting(false)
        }
    }
}

private extension Edge {
    var blotAlignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

private struct BlotRowBackground: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    let selected: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(selected ? BlotColor.selected : hovering && enabled ? BlotColor.hover : .clear))
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}

private struct BlotFocusRing: ViewModifier {
    @FocusState private var focused: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? BlotColor.focusRing : .clear, lineWidth: BlotLayout.focusRingWidth)
                    .allowsHitTesting(false)
            }
    }
}

/// Full-width 1 pt divider.
public struct BlotDivider: View {
    private let vertical: Bool

    public init(vertical: Bool = false) { self.vertical = vertical }

    public var body: some View {
        Rectangle()
            .fill(BlotColor.hairline)
            .frame(width: vertical ? BlotLayout.hairlineWidth : nil, height: vertical ? nil : BlotLayout.hairlineWidth)
            .accessibilityHidden(true)
    }
}

/// Low-prominence label with square corners.
public struct BlotTag: View {
    private let text: String
    private let mono: Bool

    public init(_ text: String, mono: Bool = false) {
        self.text = text
        self.mono = mono
    }

    public var body: some View {
        Text(text)
            .font(mono ? BlotFont.mono(12, weight: .medium) : BlotFont.role(.meta, weight: .medium))
            .foregroundStyle(BlotColor.text)
            .lineLimit(1)
            .padding(.horizontal, BlotSpace.element)
            .padding(.vertical, 2)
            .background(Rectangle().fill(BlotColor.tag))
            .fixedSize()
    }
}

/// Modal backdrop: 50 % black, no blur.
public struct BlotScrim: View {
    public init() {}
    public var body: some View {
        BlotColor.scrim.ignoresSafeArea().accessibilityHidden(true)
    }
}
