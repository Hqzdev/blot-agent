import AppKit
import SwiftUI

/// A toolbar hosting view clips tall content. Keep layout fixed and anchor the
/// expanding SwiftUI surface in a child panel at the button's window position.
struct MacTeamToolbarExpansion<Content: View>: NSViewRepresentable {
    @Environment(\.locale) private var locale
    @Binding var isPresented: Bool
    let size: CGSize
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.dismiss = { isPresented = false }
        if isPresented {
            context.coordinator.present(content: content, size: size, anchor: view, locale: locale)
        } else {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close() }

    final class Coordinator {
        var dismiss: (() -> Void)?
        private var panel: NSPanel?
        private var monitor: Any?
        private var observations: [NSObjectProtocol] = []
        private var presentationTask: Task<Void, Never>?

        func present(content: Content, size: CGSize, anchor: NSView, locale: Locale) {
            guard panel == nil else { return }
            presentationTask?.cancel()
            presentationTask = Task { @MainActor [weak self, weak anchor] in
                // The toolbar's background anchor receives its final frame after updateNSView.
                await Task.yield()
                guard !Task.isCancelled, let anchor, let window = anchor.window else { return }
                self?.show(content: content, size: size, anchor: anchor, window: window, locale: locale)
            }
        }

        private func show(content: Content, size: CGSize, anchor: NSView, window: NSWindow, locale: Locale) {
            guard panel == nil else { return }
            let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let panel = MacTeamToolbarPanel(
                contentRect: NSRect(x: rect.minX, y: rect.maxY - size.height, width: size.width, height: size.height),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.title = WorkspaceCopy.text("Create", language: locale.language.languageCode?.identifier ?? "en")
            panel.contentView = NSHostingView(rootView: content.environment(\.locale, locale))
            panel.appearance = window.effectiveAppearance
            window.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            self.panel = panel
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    dismiss?()
                    return nil
                }
                if event.type != .keyDown, event.window !== self.panel { dismiss?() }
                return event
            }
            for name in [NSWindow.willMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
                observe(name, object: window)
            }
            observe(NSApplication.didResignActiveNotification, object: NSApplication.shared)
        }

        private func observe(_ name: Notification.Name, object: AnyObject) {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss?() }
            })
        }

        func close() {
            presentationTask?.cancel()
            presentationTask = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            observations.forEach(NotificationCenter.default.removeObserver)
            monitor = nil
            observations.removeAll()
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.close()
            }
            panel = nil
        }
    }
}

private final class MacTeamToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
