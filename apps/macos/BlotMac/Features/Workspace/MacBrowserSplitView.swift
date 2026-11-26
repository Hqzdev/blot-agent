import AppKit
import SwiftUI

/// Bounds both panes, including when the window shrinks after a drag.
struct MacBrowserSplitLayout {
    static let widthPreferenceKey = "blot.browser.panelWidth"
    static let minimumWidth: CGFloat = 760
    static let minimumChatWidth: CGFloat = 336
    static let minimumBrowserWidth: CGFloat = 300
    static let dividerWidth: CGFloat = 8
    let width: CGFloat
    func browserWidth(_ requested: CGFloat) -> CGFloat {
        let maximum = max(0, width - Self.minimumChatWidth - Self.dividerWidth)
        return min(maximum, max(min(Self.minimumBrowserWidth, maximum), requested.isFinite ? requested : 500))
    }
}

struct MacBrowserSplitView<Chat: View, Browser: View>: View {
    private let resizeHitWidth: CGFloat = 24

    @AppStorage(MacBrowserSplitLayout.widthPreferenceKey) private var savedWidth = 500.0
    @State private var dragWidth: CGFloat?
    @State private var hoveringDivider = false
    @Environment(\.locale) private var locale
    var isPresented = true
    @ViewBuilder let chat: () -> Chat
    @ViewBuilder let browser: () -> Browser

    var body: some View {
        GeometryReader { geometry in
            let layout = MacBrowserSplitLayout(width: geometry.size.width)
            let width = layout.browserWidth(dragWidth ?? savedWidth)
            HStack(spacing: 0) {
                chat().frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                // The outer frame animates while the page keeps its own width.
                ZStack(alignment: .leading) {
                    if isPresented {
                        HStack(spacing: 0) {
                            MacWorkspaceDividerLine(highlighted: hoveringDivider || dragWidth != nil)
                                .frame(width: MacBrowserSplitLayout.dividerWidth)
                                .allowsHitTesting(false)
                            browser().frame(width: width)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: isPresented ? width + MacBrowserSplitLayout.dividerWidth : 0, alignment: .leading)
                .clipped()
                .allowsHitTesting(isPresented)
                .accessibilityHidden(!isPresented)
                .overlay(alignment: .leading) {
                    if isPresented {
                        MacBrowserDivider(width: width, hovering: $hoveringDivider) { requested, finished in
                            let next = layout.browserWidth(requested)
                            if finished { savedWidth = Double(next); dragWidth = nil }
                            else { dragWidth = next }
                        }
                        .frame(width: resizeHitWidth)
                        .offset(x: (MacBrowserSplitLayout.dividerWidth - resizeHitWidth) / 2)
                        .accessibilityElement()
                        .accessibilityLabel(locale.language.languageCode?.identifier == "ru" ? "Ширина браузера" : "Browser width")
                        .accessibilityValue("\(Int(width))")
                        .accessibilityAdjustableAction { direction in
                            savedWidth = Double(layout.browserWidth(width + (direction == .increment ? 40 : -40)))
                        }
                        .accessibilityIdentifier("workspace.browser.resize")
                        .onDisappear { dragWidth = nil }
                    }
                }
                .zIndex(10)
            }
        }
    }
}

private struct MacBrowserDivider: View {
    let width: CGFloat
    @Binding var hovering: Bool
    let resize: (CGFloat, Bool) -> Void
    @State private var startingWidth: CGFloat?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover(perform: hover)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let initial = startingWidth ?? width
                    startingWidth = initial
                    resize(initial - value.translation.width, false)
                }
                .onEnded { value in
                    if let initial = startingWidth { resize(initial - value.translation.width, true) }
                    startingWidth = nil
                })
            .onDisappear { hover(false) }
    }

    private func hover(_ value: Bool) {
        guard value != hovering else { return }
        hovering = value
        if value { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
    }
}
