@testable import Blot
import AppKit
import BlotDesign
import SwiftUI

@MainActor
private final class HitRecorder {
    var frames: [String: CGRect] = [:]
    var counts: [String: Int] = [:]
    func hit(_ name: String) { counts[name, default: 0] += 1 }
}

private struct HitAreaBoard: View {
    let recorder: HitRecorder
    let store: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 32) {
                MacChatIconButton(title: "Icon", symbol: "plus") { recorder.hit("icon") }.record("icon", in: recorder)
                Button("Action") { recorder.hit("primary") }.buttonStyle(WorkspaceButtonStyle()).record("primary", in: recorder)
                Button("Action") {}.buttonStyle(.glassProminent).tint(BlotColor.inverse).buttonBorderShape(.capsule).record("reference", in: recorder)
                Button("Disabled") { recorder.hit("disabled-primary") }.buttonStyle(WorkspaceButtonStyle()).disabled(true).record("disabled-primary", in: recorder)
                Button("Secondary") { recorder.hit("secondary") }.buttonStyle(WorkspaceButtonStyle(.secondary)).record("secondary", in: recorder)
                Button { recorder.hit("dismiss") } label: {
                    Image(systemName: "xmark").frame(width: 20, height: 20).blotHitArea()
                }.buttonStyle(BlotHitTargetButtonStyle(expansion: 10)).record("dismiss", in: recorder)
            }
            GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                MacChatIconButton(title: "Left", symbol: "chevron.left") { recorder.hit("left") }.record("left", in: recorder)
                MacChatIconButton(title: "Right", symbol: "chevron.right") { recorder.hit("right") }.record("right", in: recorder)
                MacChatIconButton(title: "Disabled", symbol: "trash") { recorder.hit("disabled") }.disabled(true).record("disabled", in: recorder)
                MacChatCreateButton().environment(store).record("menu", in: recorder)
            }
            }
            Button { recorder.hit("row") } label: {
                HStack { Image(systemName: "folder"); Text("Whole row"); Spacer() }.padding(8).frame(width: 260, height: 44)
            }.buttonStyle(BlotPlainButtonStyle()).record("row", in: recorder)
            Button { recorder.hit("quiet") } label: {
                HStack { Text("Quiet action"); Spacer() }.frame(width: 260, height: 36)
            }.buttonStyle(WorkspaceButtonStyle(.quiet)).record("quiet", in: recorder)
            Button { recorder.hit("workspace-row") } label: {
                HStack { Text("Content block"); Spacer() }.frame(width: 260, height: 44)
            }.buttonStyle(WorkspaceRowButtonStyle()).record("workspace-row", in: recorder)
        }.padding(40).frame(width: 640, height: 520, alignment: .topLeading)
            .background(.white).coordinateSpace(name: "hit-board")
            .environment(\.blotReduceMotion, true)
    }
}

private extension View {
    func record(_ name: String, in recorder: HitRecorder) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("hit-board")) } action: { recorder.frames[name] = $0 }
    }
}

private final class HitTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@main @MainActor
struct VerifyControlHitAreas {
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory); NSApp.activate(ignoringOtherApps: true)
        let recorder = HitRecorder()
        let host = NSHostingView(rootView: HitAreaBoard(recorder: recorder, store: WorkspaceStore(mode: .preview, route: .chat)).environment(\.colorScheme, .light))
        let window = HitTestWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await _Concurrency.Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        func frame(_ name: String) -> CGRect { guard let value = recorder.frames[name] else { fatalError("Missing control: " + name) }; return value }
        precondition(frame("icon").size == CGSize(width: 38, height: 38), "Icon artwork size must not change")
        precondition(frame("primary").size == frame("reference").size, "Native capsule layout must not grow")
        var assertions = 0
        func click(_ name: String, at point: CGPoint, expected: String?) async throws {
            let before = recorder.counts
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: 520 - point.y), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: assertions, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { throw CocoaError(.coderInvalidValue) }
                // Events stay inside this isolated fixture window; no user's app or external action is involved.
                window.sendEvent(event)
                try await _Concurrency.Task.sleep(for: .milliseconds(25))
            }
            let changed = Set(recorder.counts.keys.filter { recorder.counts[$0, default: 0] != before[$0, default: 0] })
            let intended = expected.map { Set([$0]) } ?? []
            precondition(changed == intended, "\(name): expected \(intended), got \(changed) at \(point)")
            if let expected { precondition(recorder.counts[expected, default: 0] == before[expected, default: 0] + 1, "Action must fire exactly once") }
            assertions += 1
        }
        for name in ["icon", "primary", "secondary"] {
            let rect = frame(name)
            try await click(name + " empty corner", at: CGPoint(x: rect.minX + 1, y: rect.minY + 1), expected: name)
            try await click(name + " outer margin", at: CGPoint(x: rect.minX - 2, y: rect.midY), expected: name)
            try await click(name + " outer top margin", at: CGPoint(x: rect.midX, y: rect.minY - 2), expected: name)
            try await click(name + " outside target", at: CGPoint(x: rect.minX - 16, y: rect.midY), expected: nil)
        }
        let dismiss = frame("dismiss")
        try await click("small close icon", at: CGPoint(x: dismiss.minX - 8, y: dismiss.midY), expected: "dismiss")
        for name in ["row", "quiet", "workspace-row"] {
            let rect = frame(name)
            try await click(name + " blank trailing area", at: CGPoint(x: rect.maxX - 8, y: rect.midY), expected: name)
        }
        let left = frame("left"), right = frame("right"), disabled = frame("disabled")
        try await click("left near neighbor", at: CGPoint(x: left.maxX + 2, y: left.midY), expected: "left")
        try await click("right near neighbor", at: CGPoint(x: right.minX - 2, y: right.midY), expected: "right")
        try await click("disabled center", at: CGPoint(x: disabled.midX, y: disabled.midY), expected: nil)
        try await click("disabled margin", at: CGPoint(x: disabled.minX - 2, y: disabled.midY), expected: nil)
        let disabledPrimary = frame("disabled-primary")
        try await click("disabled native halo", at: CGPoint(x: disabledPrimary.minX - 2, y: disabledPrimary.midY), expected: nil)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l" + String(window.windowNumber), FileManager.default.currentDirectoryPath + "/.build/grok-hit-targets/controls.png"]
        try capture.run(); capture.waitUntilExit()
        precondition(capture.terminationStatus == 0, "Native control snapshot must succeed")
        print("PASS: \(assertions) native mouse checks; unchanged layout; expanded margins, empty rows, disabled controls and neighboring targets.")
    }
}
