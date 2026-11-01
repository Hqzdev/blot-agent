//
//  BlotFont.swift
//  BlotDesign
//
//  System typeface only. Three sizes — caption 14, body 16, heading 24 — in weights
//  400 / 500 / 600, plus the system monospaced face for code. `blotFont` scales with the
//  person's text size (Dynamic Type, or the in-app size on Mac through `dynamicTypeSize`).
//

import SwiftUI

nonisolated public enum BlotTextRole: Sendable, CaseIterable {
    /// Metadata next to a row title (13).
    case meta
    /// Captions, row titles, buttons and labels (14).
    case caption
    /// Messages, inputs and body copy (16).
    case body
    /// Page and welcome headings (24), the largest size in the interface.
    case heading
    /// Code and identifiers (13, monospaced).
    case code

    public var size: CGFloat {
        switch self {
        case .meta: 13
        case .caption: 14
        case .body: 16
        case .heading: 24
        case .code: 13
        }
    }

    public var defaultWeight: Font.Weight {
        switch self {
        case .heading: .semibold
        default: .regular
        }
    }

    /// Extra space between lines on top of the font's own leading, matching
    /// 1.43 (caption), 1.5 (body) and 1.33 (heading) line heights.
    public var lineSpacing: CGFloat {
        switch self {
        case .meta: 2
        case .caption: 3
        case .body: 5
        case .heading: 3
        case .code: 3
        }
    }

    /// Text style the size scales with.
    public var textStyle: Font.TextStyle {
        switch self {
        case .meta: .footnote
        case .caption: .subheadline
        case .body: .body
        case .heading: .title2
        case .code: .footnote
        }
    }

    public var design: Font.Design { self == .code ? .monospaced : .default }
}

nonisolated public enum BlotFont {
    /// Fixed-size system font. Prefer `View.blotFont(_:)` where text should follow the
    /// person's text size; use this for glyph-sized text inside drawings.
    public static func system(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static func role(_ role: BlotTextRole, weight: Font.Weight? = nil, scale: CGFloat = 1) -> Font {
        .system(size: role.size * scale, weight: weight ?? role.defaultWeight, design: role.design)
    }
}

/// Applies a text role at a size that follows the environment's Dynamic Type size.
public struct BlotScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let role: BlotTextRole
    private let weight: Font.Weight

    public init(_ role: BlotTextRole, weight: Font.Weight? = nil) {
        self.role = role
        self.weight = weight ?? role.defaultWeight
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.textStyle)
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: role.design))
            .lineSpacing(role.lineSpacing)
    }
}

public extension View {
    /// System font for a text role, scaled with the person's text size.
    func blotFont(_ role: BlotTextRole, weight: Font.Weight? = nil) -> some View {
        modifier(BlotScaledFont(role, weight: weight))
    }
}
