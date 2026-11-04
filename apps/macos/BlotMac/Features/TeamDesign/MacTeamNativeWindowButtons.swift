import AppKit
import SwiftUI

/// AppKit supplies the native controls; the shared header owns their layout.
struct MacTeamNativeWindowButtons: NSViewRepresentable {
    func makeNSView(context: Context) -> ButtonHost { ButtonHost() }
    func updateNSView(_ view: ButtonHost, context: Context) { view.installButtons() }
    static func dismantleNSView(_ view: ButtonHost, coordinator: Void) { view.restoreButtons() }

    final class ButtonHost: NSView {
        private struct Control {
            let type: NSWindow.ButtonType
            let button: NSButton
            let originalHidden: Bool
        }

        private var controls: [Control] = []
        private var updateObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installButtons()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window { restoreButtons() }
            super.viewWillMove(toWindow: newWindow)
        }

        override func layout() {
            super.layout()
            for (index, control) in controls.enumerated() {
                control.button.setFrameOrigin(NSPoint(
                    x: CGFloat(index) * 22,
                    y: (bounds.height - control.button.frame.height) / 2))
            }
        }

        func installButtons() {
            guard let window else { return }
            guard controls.isEmpty else { hideTitlebarButtons(); needsLayout = true; return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: window.styleMask) else { continue }
                controls.append(Control(type: type, button: button,
                                        originalHidden: window.standardWindowButton(type)?.isHidden ?? false))
                button.target = self
                button.action = #selector(performWindowAction(_:))
                button.tag = index
                addSubview(button)
            }
            hideTitlebarButtons()
            updateObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.hideTitlebarButtons() }
            }
            needsLayout = true
        }

        private func hideTitlebarButtons() {
            for control in controls {
                if let original = window?.standardWindowButton(control.type), !original.isHidden {
                    original.isHidden = true
                }
            }
        }

        @objc private func performWindowAction(_ sender: NSButton) {
            switch sender.tag {
            case 0: window?.performClose(sender)
            case 1: window?.performMiniaturize(sender)
            default:
                if NSEvent.modifierFlags.contains(.option) { window?.performZoom(sender) }
                else { window?.toggleFullScreen(sender) }
            }
        }

        func restoreButtons() {
            if let updateObserver { NotificationCenter.default.removeObserver(updateObserver) }
            updateObserver = nil
            for control in controls {
                window?.standardWindowButton(control.type)?.isHidden = control.originalHidden
                control.button.removeFromSuperview()
            }
            controls.removeAll()
        }
    }
}
