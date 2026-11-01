//
//  Theme.swift
//  BlotMac
//
//  Mac names for the shared BlotDesign tokens. Screens keep using `K`, `KSpace` and `KFont`;
//  the values come from the package, so the Mac and iPhone apps share one monochrome system.
//  Status colours are intentionally ink: meaning is carried by icons, labels and weight.
//

import BlotDesign
import Observation
import SwiftUI

extension Color {
    /// 0xRRGGBB, opaque. Kept for user content (avatars, images); interface chrome uses `K`.
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Blot design tokens for the Mac app, backed by `BlotDesign`.
enum K {
    // Surfaces
    static let bg = BlotColor.canvas
    static let bgSidebar = BlotColor.sidebar
    static let bgChrome = BlotColor.canvas
    static let composer = BlotColor.panel
    static let composerContext = BlotColor.sidebar
    static let surface = BlotColor.panel
    static let surface2 = BlotColor.fill
    static let card = BlotColor.panel
    static let userMessage = BlotColor.fill
    static let codeBackground = BlotColor.sidebar

    // Interaction
    static let hover = BlotColor.hover
    static let selected = BlotColor.selected
    static let pressed = BlotColor.pressed
    static let border = BlotColor.hairline
    static let borderStrong = BlotColor.hairlineStrong
    static let focus = BlotColor.focusRing

    // Text
    static let text = BlotColor.text
    static let text2 = BlotColor.textSecondary
    /// Helper text people need to read uses the secondary colour; `disabled` is for controls
    /// that cannot be used and for placeholders.
    static let text3 = BlotColor.textSecondary
    static let disabled = BlotColor.textTertiary
    static let inverse = BlotColor.inverse
    static let onInverse = BlotColor.onInverse

    // Status — monochrome. Pair with `StatusTone.icon` / `InlineFeedback.Tone.icon` and a label.
    static let success = BlotColor.text
    static let danger = BlotColor.text
    static let warning = BlotColor.text
    static let successBg = BlotColor.hover
    static let dangerBg = BlotColor.pressed
    static let ember = BlotColor.accent
    static let profileAvatar = BlotColor.inverse
    static let diffAddBg = BlotColor.diffAdded
    static let diffDelBg = BlotColor.diffRemoved
    static let scrim = BlotColor.scrim
    static let graphGrid = BlotColor.dynamic(BlotColorPair(light: 0x00000008, dark: 0xFFFFFF08))
    static let edgeGray = BlotColor.edge
    static let tooltip = BlotColor.tooltip
    static let onTooltip = BlotColor.onTooltip

    // Radii: one 10 pt radius for controls, rows, fields, the composer and panels.
    static let rSm: CGFloat = 6
    static let rMd: CGFloat = BlotRadius.control
    static let rLg: CGFloat = BlotRadius.panel
    static let rXl: CGFloat = 16

    // Layout
    static let windowWidth: CGFloat = 1312
    static let windowHeight: CGFloat = 751
    static let sidebarWidth: CGFloat = BlotLayout.sidebarIdealWidth
    static let headerHeight: CGFloat = BlotLayout.headerHeight
    static let contentWidth: CGFloat = BlotLayout.conversationMaxWidth
    static let profileContentWidth: CGFloat = 880
    static let railWidth: CGFloat = 52
    static let shellToolbarHeight: CGFloat = 44
    static let sidebarRowHeight: CGFloat = 34
    static let projectSidebarMin: CGFloat = BlotLayout.sidebarMinWidth
    static let projectSidebarMax: CGFloat = BlotLayout.sidebarMaxWidth
    static let projectPanelWidth: CGFloat = 280
    static let sidebarRowSpacing: CGFloat = 2
    static let railButtonSize: CGFloat = 36
    static let controlHeight: CGFloat = BlotLayout.controlHeight
    static let controlHeightLarge: CGFloat = BlotLayout.controlHeightLarge
    static let iconButtonSize: CGFloat = BlotLayout.iconButton
    static let listTileSize: CGFloat = 32
    static let shellInset: CGFloat = 4
    static let pageInset: CGFloat = KSpace.xl
    static let pageTopInset: CGFloat = KSpace.section
    static let composerHeight: CGFloat = 98
    static let composerContextHeight: CGFloat = 36
    /// The context row sits above the input as its own line; nothing overlaps.
    static let composerContextOverlap: CGFloat = 0
    static let composerBottomInset: CGFloat = 20 - shellInset
    static let composerPetClearance: CGFloat = 36
    static let composerRadius: CGFloat = BlotRadius.control
    static let primaryBlotSize: CGFloat = 76
    static let composerBlotSize: CGFloat = 56
}

/// Spacing follows the 6 / 10 / 16 / 24 rhythm.
enum KSpace {
    static let xs: CGFloat = 4
    static let element: CGFloat = BlotSpace.element
    static let sm: CGFloat = BlotSpace.s8
    static let md: CGFloat = BlotSpace.s10
    static let lg: CGFloat = BlotSpace.panel
    static let xl: CGFloat = BlotSpace.section
    static let section: CGFloat = 32
}

// Motion tokens (KMotion), transitions and Reduce Motion handling live in shared/Motion.swift.

// MARK: - Fonts

/// In-app text size (Settings › Appearance). Views that build fonts with `KFont` read it, so
/// they redraw when it changes.
@Observable
final class KTextScale {
    static let shared = KTextScale()
    var value: CGFloat = 1
}

/// System typeface only. Sizes snap to the shared scale — 13 metadata, 14 captions and labels,
/// 16 body, 24 headings — and follow the in-app text size. Code uses the system monospaced face.
enum KFont {
    enum Weight {
        case regular, medium, semibold, bold

        var system: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold, .bold: .semibold
            }
        }
    }

    static var scale: CGFloat { KTextScale.shared.value }

    /// Snaps a requested size to the type scale. Nothing in the interface is larger than 24.
    static func tier(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<13.5: BlotTextRole.meta.size
        case ..<15.5: BlotTextRole.caption.size
        case ..<19.5: BlotTextRole.body.size
        default: BlotTextRole.heading.size
        }
    }

    static func ui(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .system(size: tier(size) * scale, weight: weight.system)
    }

    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .system(size: max(11, min(size, 16)) * scale, weight: weight.system, design: .monospaced)
    }

    /// Messages, inputs and body copy (16).
    static func body(_ weight: Weight = .regular) -> Font { ui(16, weight) }
    /// Buttons, row titles and card headers (14 medium).
    static func label(_ weight: Weight = .medium) -> Font { ui(14, weight) }
    /// Secondary row text, metadata and descriptions (13).
    static func caption(_ weight: Weight = .regular) -> Font { ui(13, weight) }
    static func sheetTitle() -> Font { ui(16, .semibold) }
    static func sidebarTitle() -> Font { ui(14, .semibold) }
    /// Page and welcome headings (24 semibold), the largest text in the app.
    static func pageTitle(_ weight: Weight = .semibold) -> Font { ui(24, weight) }
}

// MARK: - Text size

enum TextSizePreference: String, CaseIterable, Identifiable {
    case small = "Small", standard = "Default", large = "Large"
    var id: String { rawValue }
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .medium
        case .standard: .large
        case .large: .xLarge
        }
    }
    var scale: CGFloat {
        switch self {
        case .small: 0.92
        case .standard: 1
        case .large: 1.12
        }
    }
}
