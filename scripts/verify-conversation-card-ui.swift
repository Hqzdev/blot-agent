import AppKit
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

@main @MainActor
struct VerifyConversationCardUI {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw WorkspaceStorageError.invalidParameters }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        let samples = try ConversationCardSamples.samples()
        var manifest: [[String: String]] = []
        for (index, sample) in samples.enumerated() {
            for dark in [false, true] {
                let store = try ConversationCardSamples.store()
                let card = try ConversationCardSamples.card(sample, index: index)
                let root = WorkspaceConversationCardView(card: card, fallback: sample.name)
                    .environment(store).frame(width: 480).padding(36)
                    .frame(width: 740, height: 760).background(WorkspaceStyle.canvas)
                    .blotTheme(dark ? .dark : .light).environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: root)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host
                host.frame = NSRect(x: 0, y: 0, width: 740, height: 760)
                window.orderFrontRegardless()
                try await _Concurrency.Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let filename = sample.reference + "-mac-" + sample.name + (dark ? "-dark.png" : "-light.png")
                try capture(window, to: directory.appendingPathComponent(filename))
                manifest.append(["file": filename, "kind": sample.name, "reference": sample.reference + ".jpg", "method": "production SwiftUI view in native NSHostingView"])
                window.contentView = nil; window.close()
            }
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        try await VerifyMacChatInterface.render(to: directory.appendingPathComponent("shells"))
        print("PASS: all \(samples.count) production cards rendered in light and dark on the physical Mac (\(samples.count * 2) native frames). External actions were not invoked.")
    }
    static func capture(_ window: NSWindow, to url: URL) throws {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l" + String(window.windowNumber), url.path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0 else { throw WorkspaceStorageError.invalidRecord }
    }

}
