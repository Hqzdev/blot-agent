//
//  BlotMetrics.swift
//  BlotDesign
//
//  Spacing rhythm 6 / 10 / 16 / 24, one 10 pt radius for controls and panels, square tags,
//  and the layout sizes both apps share.
//

import CoreGraphics

nonisolated public enum BlotSpace {
    /// Gap between elements inside a group.
    public static let element: CGFloat = 6
    public static let s8: CGFloat = 8
    /// Padding inside rows and controls.
    public static let s10: CGFloat = 10
    public static let s12: CGFloat = 12
    /// Inner padding of panels and cards.
    public static let panel: CGFloat = 16
    public static let s20: CGFloat = 20
    /// Gap between sections.
    public static let section: CGFloat = 24
}

nonisolated public enum BlotRadius {
    /// Buttons, navigation rows, text fields, the composer, panels and menus.
    public static let control: CGFloat = 10
    public static let panel: CGFloat = 10
    /// Tags and badges keep square corners.
    public static let tag: CGFloat = 0
}

nonisolated public enum BlotLayout {
    public static let sidebarIdealWidth: CGFloat = 270
    public static let sidebarMinWidth: CGFloat = 230
    public static let sidebarMaxWidth: CGFloat = 320
    public static let headerHeight: CGFloat = 52
    /// Reading width of a conversation.
    public static let conversationMaxWidth: CGFloat = 736
    public static let controlHeight: CGFloat = 32
    public static let controlHeightLarge: CGFloat = 40
    public static let iconButton: CGFloat = 28
    /// Smallest tappable area on iPhone.
    public static let minimumTapTarget: CGFloat = 44
    /// Character above the iPhone composer.
    public static let phoneCharacterSize: CGFloat = 40
    public static let hairlineWidth: CGFloat = 1
    public static let focusRingWidth: CGFloat = 2
}
