import AppKit
import BlotDesign
import SwiftUI

/// SwiftUI owns the header. This bridge styles the frame and positions native buttons.
struct WindowChrome: NSViewRepresentable {
    @Environment(AppState.self) private var app
    func makeNSView(context: Context) -> ChromeAnchor {
        let view = ChromeAnchor(); view.state = app; return view
    }
    func updateNSView(_ view: ChromeAnchor, context: Context) { view.state = app; view.configure() }

    final class ChromeAnchor: NSView {
        var state: AppState?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            guard let window, let state else { return }
            window.title = state.shellTitle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.hasShadow = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = NSColor(K.bgChrome)
            if let frame = window.contentView?.superview {
                frame.wantsLayer = true
                frame.layer?.cornerRadius = 14
                frame.layer?.borderWidth = 1
                frame.layer?.borderColor = NSColor(K.borderStrong).cgColor
            }
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
                button.setFrameOrigin(NSPoint(x: 16 + CGFloat(index) * 23,
                    y: parent.bounds.height - K.shellToolbarHeight / 2 - button.bounds.height / 2))
            }
        }
    }
}
