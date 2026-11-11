import AppKit
import BlotAppleIntegrations
import BlotWorkspace
import Foundation
import WebKit
import SwiftUI

@MainActor @main
struct VerifyBrowserExecution {
    static var previewWindow: NSWindow?
    static func main() {
        let app = NSApplication.shared
        let preview = CommandLine.arguments.contains("--resize-preview")
        app.setActivationPolicy(preview ? .regular : .accessory)
        Task { @MainActor in
            do {
                if preview { try showResizePreview(); return }
                try await verify(); print("PASS: real WebKit browser verification completed"); exit(0)
            }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        app.run()
    }
    static func showResizePreview() throws {
        let browser = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
        _ = try browser.open("http://127.0.0.1:" + CommandLine.arguments.last! + "/second")
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1280, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Blot — browser divider verification"; window.minSize = NSSize(width: MacBrowserSplitLayout.minimumWidth, height: 480)
        window.contentView = NSHostingView(rootView: BrowserResizePreview(browser: browser)); previewWindow = window
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    static func fields(_ value: ChatJSON) -> [String: ChatJSON] { if case .object(let fields) = value { fields } else { [:] } }
    static func string(_ value: ChatJSON?) -> String { if case .string(let text) = value { text } else { "" } }
    static func value(_ result: WorkspaceBrowserResult) -> ChatJSON { if case .value(let value) = result { value } else { .null } }
    static func wait(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw WorkspaceBrowserError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    static func verifySessions(origin: String) async throws {
        let browser = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
        defer { browser.shutdown() }
        let first = WorkspaceBrowserSessionKey.agent(UUID()), second = WorkspaceBrowserSessionKey.agent(UUID())
        browser.activateSession(first)
        let a = try browser.open(origin + "/page")
        try await wait { browser.selectedTab?.loading == false }
        browser.activateSession(second)
        let b = try browser.open(origin + "/second")
        try await wait { browser.selectedTab?.loading == false }
        let scope = WorkspaceBrowserScope(sourceID: UUID(), taskID: nil, agentID: UUID())
        let readA = WorkspaceBrowserCommand(id: UUID(), name: "browser_snapshot", arguments: .object([:]), scope: scope, origins: ["*"], sessionKey: first)
        let result = fields(value(try await browser.execute(readA, binding: browser.prepare(readA))))
        precondition(string(result["tab_id"]) == a.uuidString && string(result["text"]).contains("Local test page"))
        precondition(browser.activeSession == second && browser.selectedID == b)
        let cross = WorkspaceBrowserCommand(id: UUID(), name: "browser_snapshot", arguments: .object(["tab_id": .string(b.uuidString)]), scope: scope, origins: ["*"], sessionKey: first)
        do { _ = try await browser.prepare(cross); preconditionFailure("read another agent session") } catch WorkspaceBrowserError.denied {}
        let openA = WorkspaceBrowserCommand(id: UUID(), name: "browser_open", arguments: .object(["url": .string(origin + "/page")]), scope: scope, origins: ["*"], sessionKey: first)
        _ = try await browser.execute(openA, binding: browser.prepare(openA))
        precondition(browser.activeSession == second && browser.selectedID == b && browser.liveTabCount <= 2)
        let list = WorkspaceBrowserCommand(id: UUID(), name: "browser_tabs", arguments: .object([:]), scope: scope, origins: ["*"], sessionKey: second)
        guard case .array(let tabs) = fields(value(try await browser.execute(list, binding: browser.prepare(list))))["tabs"] else { preconditionFailure("missing tabs") }
        precondition(tabs.count == 1 && string(fields(tabs[0])["tab_id"]) == b.uuidString)
        print("PASS: background agent reads/opens only its own session, does not select another agent's page, and shares the two-WebView budget")
    }
    static func verify() async throws {
        for window in [760.0, 900, 1280, 1920, 2560] {
            let layout = MacBrowserSplitLayout(width: window)
            for requested in [-100.0, 300, 500, 2000, .infinity, .nan] {
                let width = layout.browserWidth(requested)
                precondition(width.isFinite && width >= 300 && width <= window - MacBrowserSplitLayout.minimumChatWidth - MacBrowserSplitLayout.dividerWidth)
                precondition(window - width - MacBrowserSplitLayout.dividerWidth >= MacBrowserSplitLayout.minimumChatWidth)
            }
        }
        print("PASS: browser divider bounds preserve at least 336 points for the chat across window sizes and extreme saved widths")
        guard CommandLine.arguments.count == 2 else { throw WorkspaceBrowserError.invalidURL }
        let origin = "http://127.0.0.1:" + CommandLine.arguments[1]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlotBrowserVerification-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloadURL = directory.appendingPathComponent("browser-test.txt")
        let browser = WorkspaceBrowserController(profileID: UUID(), directory: directory, ephemeral: true, chooseDownload: { _ in downloadURL })
        defer { browser.shutdown() }
        let scope = WorkspaceBrowserScope(sourceID: UUID(), taskID: nil, agentID: UUID())
        func command(_ name: String, _ args: [String: ChatJSON], id: UUID = UUID()) -> WorkspaceBrowserCommand {
            .init(id: id, name: name, arguments: .object(args), scope: scope, origins: [origin])
        }
        let open = command("browser_open", ["url": .string(origin + "/page")])
        let binding = try await browser.prepare(open)
        let ready = fields(value(try await browser.execute(open, binding: binding)))
        let tabID = string(ready["tab_id"]), document = string(ready["document_id"])
        let id = UUID(uuidString: tabID)!
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Blot — isolated browser verification"; window.contentView = browser.webView(for: id); window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        func snapshot() async throws -> ChatJSON {
            let request = command("browser_snapshot", ["tab_id": .string(tabID)])
            return value(try await browser.execute(request, binding: browser.prepare(request)))
        }
        let page = fields(try await snapshot())
        guard case .array(let elements) = page["elements"] else { throw WorkspaceBrowserError.unavailable }
        func element(_ label: String) -> String { elements.map(fields).first { string($0["label"]) == label }.map { string($0["id"]) } ?? "" }
        precondition(!element("Note").isEmpty && !element("Password").isEmpty)
        precondition(!string(page["text"]).contains("never-expose-this"))
        let encodedPage = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
        precondition(!encodedPage.contains("private-code-never-expose") && !encodedPage.contains("private-card-never-expose"))
        let popup = command("browser_click", ["tab_id": .string(tabID), "document_id": .string(document), "element_id": .string(element("New tab"))])
        _ = try await browser.execute(popup, binding: browser.prepare(popup))
        try await wait { browser.tabs.count == 2 && browser.tabs.contains { $0.id != id && !$0.loading && $0.title == "Second page" } }
        try browser.select(id)
        let foreign = WorkspaceBrowserCommand(id: UUID(), name: "browser_snapshot", arguments: .object(["tab_id": .string(tabID)]),
            scope: .init(sourceID: UUID(), taskID: nil, agentID: UUID()), origins: [origin])
        do { _ = try await browser.prepare(foreign); preconditionFailure("another task accessed the tab") } catch WorkspaceBrowserError.denied {}
        let sensitive = command("browser_screenshot", ["tab_id": .string(tabID)])
        do { _ = try await browser.execute(sensitive, binding: browser.prepare(sensitive)); preconditionFailure("secret field screenshot escaped") } catch WorkspaceBrowserError.denied {}
        let click = command("browser_click", ["tab_id": .string(tabID), "document_id": .string(document), "element_id": .string(element("Change status"))])
        let before = try await browser.prepare(click)
        _ = try await browser.webView(for: id)!.callAsyncJavaScript("document.getElementById('change').textContent='Changed by user';", contentWorld: .page)
        do { _ = try await browser.execute(click, binding: before); preconditionFailure("stale click ran") } catch WorkspaceBrowserError.stalePage {}
        let type = command("browser_type", ["tab_id": .string(tabID), "document_id": .string(document), "element_id": .string(element("Note")), "text": .string("typed once")])
        _ = try await browser.execute(type, binding: browser.prepare(type))
        try await wait { browser.selectedTab?.unsaved == true }
        let current = try await browser.webView(for: id)!.callAsyncJavaScript("return document.getElementById('note').value;", contentWorld: .page) as? String
        precondition(current == "typed once")
        let secret = command("browser_type", ["tab_id": .string(tabID), "document_id": .string(document), "element_id": .string(element("Password")), "text": .string("forbidden")])
        do { _ = try await browser.prepare(secret); preconditionFailure("password was editable by agent") } catch WorkspaceBrowserError.stalePage {}
        for label in ["Verification code", "Card number"] {
            let input = command("browser_type", ["tab_id": .string(tabID), "document_id": .string(document), "element_id": .string(element(label)), "text": .string("forbidden")])
            do { _ = try await browser.prepare(input); preconditionFailure("manual field was editable by agent") } catch WorkspaceBrowserError.stalePage {}
        }
        do { try browser.close(id); preconditionFailure("unsaved form was silently closed") } catch WorkspaceBrowserError.unsavedChanges {}
        try browser.close(id, discard: true)
        print("PASS: real navigation, DOM snapshot, exact element binding, text input, password exclusion and unsaved-form protection")
        print("PASS: target-blank opens inside Blot; another scope and sensitive screenshots are denied")

        let second = command("browser_open", ["url": .string(origin + "/second")])
        let secondID = fields(value(try await browser.execute(second, binding: browser.prepare(second))))["tab_id"]
        let shot = command("browser_screenshot", ["tab_id": secondID!])
        window.contentView = browser.webView(for: UUID(uuidString: string(secondID))!)
        if case .image(let bytes) = try await browser.execute(shot, binding: browser.prepare(shot)) { precondition(bytes.count > 500) } else { preconditionFailure("missing screenshot") }
        for _ in 0..<3 { _ = try browser.open(origin + "/second") }
        precondition(browser.liveTabCount <= 2)
        print("PASS: native viewport screenshot and at most two live WebViews across multiple tabs")

        _ = try browser.open(origin + "/download")
        try await wait { browser.downloads.contains { $0.state == "completed" } }
        let downloaded = try String(contentsOf: downloadURL, encoding: .utf8)
        precondition(downloaded == "Blot browser download verified\n")
        precondition(!browser.sessionDownloads.isEmpty)
        browser.activateSession(.agent(UUID()))
        precondition(browser.sessionDownloads.isEmpty)
        browser.activateSession(.workspace)
        print("PASS: actual WKDownload writes only to the chosen destination and remains in the app download list")

        let slow = command("browser_open", ["url": .string(origin + "/slow")])
        let slowBinding = try await browser.prepare(slow)
        let loading = Task { try await browser.execute(slow, binding: slowBinding) }
        try await Task.sleep(for: .milliseconds(100)); browser.stop(scope: scope)
        do { _ = try await loading.value; preconditionFailure("stopped navigation completed") } catch {}
        precondition(!browser.tabs.contains { $0.loading && $0.id == slow.id })
        print("PASS: stopping a browser scope ends pending navigation without replay")
        let pinned = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
        defer { pinned.shutdown() }
        for _ in 0..<2 {
            let id = try pinned.open(origin + "/page")
            try await wait { pinned.selectedTab?.loading == false }
            _ = try await pinned.webView(for: id)!.callAsyncJavaScript("document.getElementById('note').value='unsaved'; document.getElementById('note').dispatchEvent(new Event('input',{bubbles:true}));", contentWorld: .page)
            try await wait { pinned.selectedTab?.unsaved == true }
        }
        do { _ = try pinned.open(origin + "/second"); preconditionFailure("unsaved form evicted") } catch WorkspaceBrowserError.busy {}
        precondition(pinned.liveTabCount == 2 && pinned.tabs.allSatisfy(\.unsaved))
        print("PASS: two dirty forms exhaust the live-view budget without silent eviction")
        let active = command("browser_snapshot", [:])
        let selectedBinding = try await pinned.prepare(active)
        let selected = fields(value(try await pinned.execute(active, binding: selectedBinding)))
        precondition(selected["read_only_user_tab"] == .bool(true) && string(selected["text"]).contains("Local test page"))
        let manualClick = command("browser_click", ["tab_id": .string(selectedBinding.tabID.uuidString), "document_id": .string(selectedBinding.documentID.uuidString), "element_id": .string("1:0")])
        do { _ = try await pinned.prepare(manualClick); preconditionFailure("manual tab accepted a write") } catch WorkspaceBrowserError.denied {}
        let denied = WorkspaceBrowserCommand(id: UUID(), name: "browser_snapshot", arguments: .object([:]), scope: scope, origins: ["https://another.example"])
        do { _ = try await pinned.prepare(denied); preconditionFailure("ungranted origin was read") } catch WorkspaceBrowserError.denied {}
        try pinned.select(pinned.tabs.first!.id)
        do { _ = try await pinned.execute(active, binding: selectedBinding); preconditionFailure("switched tab reused old binding") } catch WorkspaceBrowserError.stalePage {}
        print("PASS: selected manual tab is readable with the allowed origin; writes, other origins and stale selection are denied")
        try await verifySessions(origin: origin)
        try await BrowserModelVerification.run(origin: origin, directory: directory)
        try await BrowserModelVerification.selectedTab(origin: origin, directory: directory, group: false)
        try await BrowserModelVerification.selectedTab(origin: origin, directory: directory, group: true)
        try await BrowserModelVerification.selectedTab(origin: origin, directory: directory, group: false, automatic: true)
        try await BrowserModelVerification.selectedTab(origin: origin, directory: directory, group: true, automatic: true)
        try await BrowserModelVerification.run(origin: origin, directory: directory.appendingPathComponent("auto-open"), automatic: true)
        let automatic = WorkspaceBrowserController(profileID: UUID(), ephemeral: true)
        defer { automatic.shutdown() }
        let first = try automatic.open(origin + "/page?secret=do-not-list")
        try await wait { automatic.selectedTab?.loading == false }
        for _ in 0..<2 { _ = try automatic.open(origin + "/second"); try await wait { automatic.selectedTab?.loading == false } }
        let listing = WorkspaceBrowserCommand(id: UUID(), name: "browser_tabs", arguments: .object([:]), scope: scope, origins: ["*"])
        let listed = fields(value(try await automatic.execute(listing, binding: automatic.prepare(listing))))
        guard case .array(let listedTabs) = listed["tabs"] else { throw WorkspaceBrowserError.unknown }
        precondition(listedTabs.count == 3 && !listedTabs.contains { string(fields($0)["url"]).contains("secret=") })
        let inspect = WorkspaceBrowserCommand(id: UUID(), name: "browser_snapshot", arguments: .object(["tab_id": .string(first.uuidString)]), scope: scope, origins: ["*"])
        let inspected = fields(value(try await automatic.execute(inspect, binding: automatic.prepare(inspect))))
        precondition(string(inspected["text"]).contains("Local test page") && automatic.liveTabCount <= 2)
        print("PASS: built-in browser lists and reads existing user tabs, resumes a suspended tab and preserves the live-view limit")
    }
}

private struct BrowserResizePreview: View {
    let browser: WorkspaceBrowserController
    var body: some View {
        MacBrowserSplitView {
            VStack { Text("Чат остаётся видимым").font(.title); Text("Перетащите разделитель влево и вправо") }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } browser: {
            if let id = browser.selectedID, let view = browser.webView(for: id) { BrowserVerificationSurface(view: view) }
        }
    }
}

private struct BrowserVerificationSurface: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> WKWebView { view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
