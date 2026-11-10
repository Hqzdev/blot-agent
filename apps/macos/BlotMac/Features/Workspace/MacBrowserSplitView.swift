import AppKit
import SwiftUI

/// Bounds both panes, including when the window shrinks after a drag.
struct MacBrowserSplitLayout {
    static let minimumWidth: CGFloat = 760
    static let minimumChatWidth: CGFloat = 420
    static let dividerWidth: CGFloat = 8
    let width: CGFloat
    func browserWidth(_ requested: CGFloat) -> CGFloat {
        let maximum = min(1000, max(0, width - Self.minimumChatWidth - Self.dividerWidth))
        return min(maximum, max(min(300, maximum), requested.isFinite ? requested : 500))
    }
}

struct MacBrowserSplitView<Chat: View, Browser: View>: View {
    @AppStorage("blot.browser.panelWidth") private var savedWidth = 500.0
    @State private var dragWidth: CGFloat?
    @ViewBuilder let chat: () -> Chat
    @ViewBuilder let browser: () -> Browser

    var body: some View {
        GeometryReader { geometry in
            let layout = MacBrowserSplitLayout(width: geometry.size.width)
            let width = layout.browserWidth(dragWidth ?? savedWidth)
            HStack(spacing: 0) {
                chat().frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                MacBrowserDivider(width: width) { requested, finished in
                    let next = layout.browserWidth(requested)
                    if finished { savedWidth = Double(next); dragWidth = nil }
                    else { dragWidth = next }
                }
                    .frame(width: MacBrowserSplitLayout.dividerWidth)
                    .overlay { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1).allowsHitTesting(false) }
                    .accessibilityElement()
                    .accessibilityLabel("Ширина браузера")
                    .accessibilityValue("\(Int(width))")
                    .accessibilityAdjustableAction { direction in
                        savedWidth = Double(layout.browserWidth(width + (direction == .increment ? 40 : -40)))
                    }
                    .accessibilityIdentifier("workspace.browser.resize")
                browser().frame(width: width)
            }
        }
    }
}

/// AppKit keeps mouse capture when the pointer crosses the embedded WKWebView.
private struct MacBrowserDivider: NSViewRepresentable {
    let width: CGFloat
    let resize: (CGFloat, Bool) -> Void
    func makeNSView(context: Context) -> DividerView { DividerView() }
    func updateNSView(_ view: DividerView, context: Context) { view.width = width; view.resize = resize }

    final class DividerView: NSView {
        var width: CGFloat = 500
        var resize: ((CGFloat, Bool) -> Void)?
        private var startX: CGFloat = 0
        private var startWidth: CGFloat = 0
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func mouseDown(with event: NSEvent) { startX = event.locationInWindow.x; startWidth = width }
        override func mouseDragged(with event: NSEvent) { resize?(startWidth - (event.locationInWindow.x - startX), false) }
        override func mouseUp(with event: NSEvent) { resize?(startWidth - (event.locationInWindow.x - startX), true) }
    }
}
