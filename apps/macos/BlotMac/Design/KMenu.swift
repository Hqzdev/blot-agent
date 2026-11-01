//
//  KMenu.swift
//  BlotMac
//
//  App-styled dropdown menus. Replaces native NSMenu popups so every menu uses
//  Blot tokens (surface, strong border, 8 pt rows, Hugeicons) like the product switcher.
//

import AppKit
import BlotDesign
import SwiftUI

// MARK: - Items

struct KMenuItem: Identifiable {
    enum Kind { case action, header, divider }

    let id = UUID()
    var kind: Kind = .action
    var title: String = ""
    var icon: String?
    var selected = false
    var destructive = false
    var action: () -> Void = {}

    static func button(_ title: String, icon: String? = nil, selected: Bool = false,
                       destructive: Bool = false, action: @escaping () -> Void) -> KMenuItem {
        KMenuItem(title: title, icon: icon, selected: selected, destructive: destructive, action: action)
    }

    static func header(_ title: String) -> KMenuItem { KMenuItem(kind: .header, title: title) }

    static var divider: KMenuItem { KMenuItem(kind: .divider) }

    /// Single-choice list: one row per option, a check on the current value.
    static func choices(_ options: [String], selected: String, select: @escaping (String) -> Void) -> [KMenuItem] {
        options.map { option in .button(option, selected: option == selected) { select(option) } }
    }
}

// MARK: - Trigger

/// Wraps any label in a button that opens an app-styled menu below it.
struct KMenu<Label: View>: View {
    var minWidth: CGFloat = 180
    var alignment: HorizontalAlignment = .leading
    let items: () -> [KMenuItem]
    @ViewBuilder var label: () -> Label

    @State private var anchor = KMenuAnchor()
    @State private var isOpen = false

    init(minWidth: CGFloat = 180, alignment: HorizontalAlignment = .leading,
         items: @escaping () -> [KMenuItem], @ViewBuilder label: @escaping () -> Label) {
        self.minWidth = minWidth
        self.alignment = alignment
        self.items = items
        self.label = label
    }

    var body: some View {
        Button(action: toggle) { label() }
            .buttonStyle(KIconButtonStyle())
            .kFocusRing()
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .background(KMenuAnchorView(anchor: anchor))
            .onDisappear { if isOpen { KMenuController.shared.close() } }
    }

    private func toggle() {
        guard !isOpen, let view = anchor.view, let window = view.window else {
            KMenuController.shared.close()
            return
        }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        isOpen = true
        KMenuController.shared.show(items: items(), minWidth: minWidth, below: rect, in: window,
                                     alignTrailing: alignment == .trailing) { isOpen = false }
    }
}

/// Reference box so the trigger can find its NSView without re-rendering.
final class KMenuAnchor {
    weak var view: NSView?
}

struct KMenuAnchorView: NSViewRepresentable {
    let anchor: KMenuAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

// MARK: - Panel

private final class KMenuPanel: NSPanel {
    var acceptsKeyFocus = false
    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class KMenuController {
    static let shared = KMenuController()
    private enum Placement { case below, profile, navigation, dropdown }

    /// Transparent margin around the card so the panel can be positioned freely near screen edges.
    private let inset = NSEdgeInsets(top: 4, left: 24, bottom: 36, right: 24)
    private let gap: CGFloat = 6

    private var panel: NSPanel?
    private weak var parent: NSWindow?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var onClose: (() -> Void)?

    func show(items: [KMenuItem], minWidth: CGFloat, below rect: NSRect, in window: NSWindow,
              alignTrailing: Bool, onClose: @escaping () -> Void) {
        let content = KMenuPanelView(items: items, minWidth: minWidth, inset: inset) { [weak self] in
            self?.close()
        }
        present(content, near: rect, in: window, alignTrailing: alignTrailing, placement: .below, onClose: onClose)
    }

    func showProfile<Content: View>(_ content: Content, beside rect: NSRect, in window: NSWindow,
                                   onClose: @escaping () -> Void) {
        let padded = content.padding(EdgeInsets(top: inset.top, leading: inset.left,
                                               bottom: inset.bottom, trailing: inset.right))
        present(padded, near: rect, in: window, alignTrailing: false, placement: .profile, onClose: onClose)
    }

    func showNavigation<Content: View>(_ content: Content, beside rect: NSRect, in window: NSWindow,
                                      onClose: @escaping () -> Void) {
        let padded = content.padding(EdgeInsets(top: inset.top, leading: inset.left,
                                               bottom: inset.bottom, trailing: inset.right))
        present(padded, near: rect, in: window, alignTrailing: false, placement: .navigation, onClose: onClose)
    }

    func showDropdown<Content: View>(_ content: Content, below rect: NSRect, in window: NSWindow,
                                    title: String, onClose: @escaping () -> Void) {
        let padded = content.padding(EdgeInsets(top: inset.top, leading: inset.left,
                                               bottom: inset.bottom, trailing: inset.right))
        present(padded, near: rect, in: window, alignTrailing: false, placement: .dropdown, title: title, onClose: onClose)
    }

    private func present<Content: View>(_ content: Content, near rect: NSRect, in window: NSWindow,
                                       alignTrailing: Bool, placement: Placement, title: String? = nil,
                                       onClose: @escaping () -> Void) {
        close()
        self.onClose = onClose
        parent = window
        let host = NSHostingView(rootView: content)
        host.appearance = window.effectiveAppearance
        let size = host.fittingSize

        let panel = KMenuPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsKeyFocus = true
        panel.title = title ?? (placement == .navigation ? "More" : placement == .profile ? "Profile" : "")
        panel.appearance = window.effectiveAppearance
        panel.contentView = host

        let cardWidth = size.width - inset.left - inset.right
        let cardHeight = size.height - inset.top - inset.bottom
        let beside = placement == .profile || placement == .navigation
        var x = (beside ? rect.maxX + gap : alignTrailing ? rect.maxX - cardWidth : rect.minX) - inset.left
        var y: CGFloat
        switch placement {
        case .below, .dropdown: y = rect.minY - gap - cardHeight - inset.bottom
        case .profile: y = rect.minY - 8 - inset.bottom
        case .navigation: y = rect.maxY + 2 - cardHeight - inset.bottom
        }
        if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
            if !beside && y + inset.bottom < screen.minY { y = rect.maxY + gap - inset.bottom }
            y = min(max(y, screen.minY - inset.bottom), screen.maxY - size.height + inset.top)
            x = min(max(x, screen.minX - inset.left), screen.maxX - size.width + inset.right)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        self.panel = panel
        if panel.acceptsKeyFocus { panel.makeKey() }

        let mouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel { return event }
            self.close()
            return nil
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            self?.close()
            return nil
        }
        monitors = [mouse, keys].compactMap { $0 }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.panel?.isKeyWindow != true { self?.close() }
                }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
        ]
    }

    func close() {
        let restoreFocus = panel?.isKeyWindow == true
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let panel {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        if restoreFocus { parent?.makeKey() }
        panel = nil
        parent = nil
        let callback = onClose
        onClose = nil
        callback?()
    }
}

// MARK: - Content

private struct KMenuPanelView: View {
    let items: [KMenuItem]
    let minWidth: CGFloat
    let inset: NSEdgeInsets
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                switch item.kind {
                case .divider:
                    HDivider().padding(.vertical, 4).padding(.horizontal, 6)
                case .header:
                    Text(item.title)
                        .font(KFont.caption(.medium))
                        .foregroundStyle(K.text3)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                case .action:
                    KMenuRow(item: item) {
                        dismiss()
                        item.action()
                    }
                }
            }
        }
        .padding(6)
        .frame(minWidth: minWidth, alignment: .leading)
        .fixedSize()
        .kPopover()
        .padding(EdgeInsets(top: inset.top, leading: inset.left, bottom: inset.bottom, trailing: inset.right))
    }
}

private struct KMenuRow: View {
    let item: KMenuItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = item.icon {
                    KIcon(icon, size: 14, color: item.destructive ? K.danger : K.text2)
                }
                Text(item.title)
                    .font(KFont.ui(13))
                    .foregroundStyle(item.destructive ? K.danger : K.text)
                    .lineLimit(1)
                Spacer(minLength: 16)
                if item.selected {
                    KIcon("check", size: 14, color: K.text)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
            .kHover(radius: K.rMd)
        }
        .buttonStyle(KIconButtonStyle())
        .kFocusRing(radius: K.rMd)
        .accessibilityAddTraits(item.selected ? .isSelected : [])
    }
}
