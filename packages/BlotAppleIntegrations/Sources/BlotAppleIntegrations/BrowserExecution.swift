import BlotWorkspace
import CryptoKit
import Foundation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension WorkspaceBrowserController {
    public func beginManual(session: WorkspaceBrowserSessionKey, tabID: UUID) async throws {
        guard let tab = tabs.first(where: { $0.id == tabID && $0.sessionKey == session }) else { throw WorkspaceBrowserError.denied }
        pauseAgent(in: session)
        for item in tabs where item.sessionKey == session { pages[item.id]?.view.stopLoading() }
        noteAgentSite(tab)
        if activeSession == session { try select(tab.id) }
    }
    public func endManual(session: WorkspaceBrowserSessionKey) async { manualSessions.remove(session) }
    public func prepare(_ command: WorkspaceBrowserCommand) async throws -> WorkspaceBrowserBinding {
        guard !stopped, WorkspaceBrowserCatalog.toolIDs.contains(command.name) else { throw WorkspaceBrowserError.unavailable }
        while manualSessions.contains(command.sessionKey) {
            try Task.checkCancellation()
            guard !stopped else { throw WorkspaceBrowserError.unavailable }
            try await Task.sleep(for: .milliseconds(100))
        }
        let arguments = try AppleArguments(command.arguments)
        if command.name == "browser_tabs" { return .init(tabID: command.id, documentID: command.id, url: "") }
        if command.name == "browser_open" {
            let url = try WorkspaceBrowserURL.validated(arguments.required("url"))
            let origin = try WorkspaceBrowserURL.origin(url)
            guard command.origins.contains("*") || command.origins.contains(origin) else { throw WorkspaceBrowserError.denied }
            if let tab = tabs.first(where: { $0.id == command.id }) {
                guard tab.scope == command.scope, tab.sessionKey == command.sessionKey, tab.initialURL == url, !tab.stopped else { throw WorkspaceBrowserError.denied }
                return .init(tabID: tab.id, documentID: tab.documentID, url: url.absoluteString)
            }
            return .init(tabID: command.id, documentID: command.id, url: url.absoluteString)
        }
        let tab = try ownedTab(arguments, command: command)
        if command.name == "browser_snapshot" || command.name == "browser_attach" {
            if pages[tab.id] == nil { try activatePage(tab) }
            if let page = pages[tab.id], tab.loading || page.view.isLoading { try await page.waitForLoad() }
        }
        guard pages[tab.id] != nil, !tab.loading, let url = tab.url else { throw WorkspaceBrowserError.stalePage }
        let document = tab.documentID
        let revision = tab.interactionRevision
        if WorkspaceBrowserCatalog.recordsAction(command.name) {
            guard let page = pages[tab.id], !busyTabs.contains(tab.id) else { throw WorkspaceBrowserError.stalePage }
            let suppliedDocument = arguments["document_id"]
            if command.name == "browser_attach" {
                guard suppliedDocument == nil || suppliedDocument.flatMap(UUID.init(uuidString:)) == document else { throw WorkspaceBrowserError.stalePage }
                return .init(tabID: tab.id, documentID: document, url: url.absoluteString, interactionRevision: revision)
            }
            guard suppliedDocument.flatMap(UUID.init(uuidString:)) == document else { throw WorkspaceBrowserError.stalePage }
            let element = try arguments.required("element_id")
            let value = command.name == "browser_purchase"
                ? try await purchaseTarget(page, element: element)
                : try await page.script(BrowserDOM.target, arguments: ["element": element, "kind": command.name])
            guard case .string(let target) = value, target.utf8.count < 4096, tab.documentID == document,
                  tab.url == url, tab.interactionRevision == revision, !manualSessions.contains(command.sessionKey) else { throw WorkspaceBrowserError.stalePage }
            return .init(tabID: tab.id, documentID: document, url: url.absoluteString, target: target, interactionRevision: revision)
        }
        return .init(tabID: tab.id, documentID: document, url: url.absoluteString, interactionRevision: revision)
    }
    public func execute(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserResult {
        try Task.checkCancellation()
        guard !stopped, !manualSessions.contains(command.sessionKey) else { throw WorkspaceBrowserError.unavailable }
        let arguments = try AppleArguments(command.arguments)
        let selectedID = selectedID(in: command.sessionKey)
        if command.name == "browser_tabs" {
            guard try await prepare(command) == binding else { throw WorkspaceBrowserError.stalePage }
            let visible = tabs.filter { tab in
                guard tab.sessionKey == command.sessionKey, let url = tab.url, let origin = try? WorkspaceBrowserURL.origin(url), command.origins.contains("*") || command.origins.contains(origin) else { return false }
                return tab.scope == nil || tab.scope == command.scope
            }
            return .value(.object(["tabs": .array(visible.map { tab in
                .object(["tab_id": .string(tab.id.uuidString), "title": .string(tab.title), "url": .string(tab.url.flatMap(WorkspaceBrowserURL.restorable)?.absoluteString ?? ""), "selected": .bool(tab.id == selectedID), "live": .bool(tab.isLive)])
            })]))
        }
        if command.name == "browser_open" {
            guard try await prepare(command) == binding else { throw WorkspaceBrowserError.stalePage }
            let tab: BrowserTab
            if let existing = tabs.first(where: { $0.id == binding.tabID }) { tab = existing }
            else {
                guard tabs.count < 32 else { throw WorkspaceBrowserError.busy }
                tab = BrowserTab(id: binding.tabID, url: URL(string: binding.url), scope: command.scope, origins: command.origins, sessionKey: command.sessionKey)
                try createPage(tab); tabsAppend(tab, presentsBrowser: false); pages[tab.id]?.load(URL(string: binding.url)!)
            }
            guard let page = pages[tab.id] else { throw WorkspaceBrowserError.stalePage }
            guard busyTabs.insert(tab.id).inserted else { throw WorkspaceBrowserError.busy }
            defer { busyTabs.remove(tab.id) }
            noteAgentSite(tab)
            try await page.waitForLoad(); return .value(state(tab))
        }
        let tab = try ownedTab(arguments, command: command)
        guard tab.id == binding.tabID, tab.documentID == binding.documentID, tab.url?.absoluteString == binding.url,
              tab.interactionRevision == binding.interactionRevision,
              let page = pages[tab.id], busyTabs.insert(tab.id).inserted else { throw WorkspaceBrowserError.stalePage }
        defer { busyTabs.remove(tab.id) }
        noteAgentSite(tab)
        switch command.name {
        case "browser_attach":
            guard let url = tab.url else { throw WorkspaceBrowserError.stalePage }
            attachments[tab.id] = .init(scope: command.scope, origin: try WorkspaceBrowserURL.origin(url))
            return .value(.object([
                "state": .string("attached"), "access": .string("attached"),
                "tab_id": .string(tab.id.uuidString), "document_id": .string(tab.documentID.uuidString)
            ]))
        case "browser_snapshot":
            let value = try await page.script(BrowserDOM.snapshot)
            guard case .object(var fields) = value, tab.documentID == binding.documentID, tab.url?.absoluteString == binding.url,
                  (try? ownedTab(arguments, command: command)) === tab else { throw WorkspaceBrowserError.stalePage }
            fields["tab_id"] = .string(tab.id.uuidString); fields["document_id"] = .string(tab.documentID.uuidString)
            fields["url"] = .string(binding.url); fields["title"] = .string(tab.title)
            let access = tab.scope == command.scope ? "owned" : attachments[tab.id]?.scope == command.scope ? "attached" : "read_only"
            fields["access"] = .string(access)
            fields["read_only_user_tab"] = .bool(access == "read_only")
            return .value(.object(fields))
        case "browser_click", "browser_type", "browser_purchase":
            guard (arguments["text"] ?? "").utf8.count <= 8192 else { throw WorkspaceBrowserError.denied }
            let element = try arguments.required("element_id")
            let expected: String
            if command.name == "browser_purchase" {
                guard try await purchaseTarget(page, element: element) == .string(binding.target),
                      let saved = try JSONSerialization.jsonObject(with: Data(binding.target.utf8)) as? [String: String], let target = saved["target"] else { throw WorkspaceBrowserError.stalePage }
                expected = target
            } else { expected = binding.target }
            let targetArguments = ["element": element, "expected": expected, "url": binding.url]
            tab.agentPointer = nil
            let point = try await page.script(BrowserDOM.pointer, arguments: targetArguments)
            #if os(macOS)
            if activeSession == command.sessionKey, selectedID == tab.id,
               case .object(let coordinates) = point, case .number(let x) = coordinates["x"], case .number(let y) = coordinates["y"],
               x.isFinite, y.isFinite {
                tab.agentPointer = .init(x: x, y: y, operation: command.name)
                if presented { try await Task.sleep(for: .milliseconds(240)) }
            }
            #endif
            try Task.checkCancellation()
            guard !manualSessions.contains(command.sessionKey), !stopped, !tab.loading,
                  tab.documentID == binding.documentID, tab.interactionRevision == binding.interactionRevision,
                  tab.url?.absoluteString == binding.url, (try? ownedTab(arguments, command: command)) === tab else { throw WorkspaceBrowserError.stalePage }
            if command.name == "browser_purchase", try await purchaseTarget(page, element: element) != .string(binding.target) {
                throw WorkspaceBrowserError.stalePage
            }
            try Task.checkCancellation()
            guard !manualSessions.contains(command.sessionKey), tab.documentID == binding.documentID,
                  tab.interactionRevision == binding.interactionRevision else { throw WorkspaceBrowserError.stalePage }
            if let pointer = tab.agentPointer {
                tab.agentPointer = .init(x: pointer.x, y: pointer.y, operation: pointer.operation, activated: true)
            }
            var actionArguments: [String: Any] = targetArguments
            actionArguments["kind"] = command.name
            actionArguments["text"] = arguments["text"] ?? ""
            actionArguments["cursorX"] = tab.agentPointer?.x ?? -1
            actionArguments["cursorY"] = tab.agentPointer?.y ?? -1
            if command.name != "browser_type" { page.view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true }
            defer { page.view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = false }
            let result: ChatJSON
            do { result = try await page.script(BrowserDOM.action, arguments: actionArguments) }
            catch { tab.agentPointer = nil; throw error }
            if case .object(var fields) = result {
                fields["tabs"] = .array(tabs.filter { $0.scope == command.scope }.map(state))
                return .value(.object(fields))
            }
            return .value(result)
        case "browser_scroll": return .value(try await page.script(BrowserDOM.scroll, arguments: ["direction": arguments["direction"] ?? "down"]))
        case "browser_back":
            guard let destination = page.view.backForwardList.backItem?.url, permits(destination, tab: tab),
                  permitsAgentNavigation(destination, tab: tab) else { throw WorkspaceBrowserError.denied }
            try back(tab.id); try await page.waitForLoad(); return .value(state(tab))
        case "browser_close": try close(tab.id); return .value(.object(["state": .string("closed")]))
        case "browser_screenshot":
            if tab.sensitiveInput { throw WorkspaceBrowserError.denied }
            if try await page.script(BrowserDOM.sensitive) == .bool(true) { throw WorkspaceBrowserError.denied }
            let data = try await page.snapshot()
            guard tab.documentID == binding.documentID else { throw WorkspaceBrowserError.stalePage }
            return .image(data)
        default: throw WorkspaceBrowserError.denied
        }
    }
    private func purchaseTarget(_ page: BrowserPage, element: String) async throws -> ChatJSON {
        guard case .string(let target) = try await page.script(BrowserDOM.target, arguments: ["element": element, "kind": "browser_purchase"]),
              case .string(let review) = try await page.script(BrowserDOM.purchaseReview), review.utf8.count <= 256_000 else { throw WorkspaceBrowserError.stalePage }
        let digest = SHA256.hash(data: Data(review.utf8)).map { String(format: "%02x", $0) }.joined()
        let data = try JSONSerialization.data(withJSONObject: ["target": target, "digest": digest], options: [.sortedKeys])
        return .string(String(decoding: data, as: UTF8.self))
    }
    private func ownedTab(_ arguments: AppleArguments, command: WorkspaceBrowserCommand) throws -> BrowserTab {
        let selectedID = selectedID(in: command.sessionKey)
        let id: UUID?
        if let raw = arguments["tab_id"] { id = UUID(uuidString: raw) }
        else { id = ["browser_snapshot", "browser_attach"].contains(command.name) ? selectedID : nil }
        guard let id, let tab = tabs.first(where: { $0.id == id }), tab.sessionKey == command.sessionKey,
              let url = tab.url else { throw WorkspaceBrowserError.denied }
        let origin = try WorkspaceBrowserURL.origin(url)
        guard command.origins.contains("*") || command.origins.contains(origin) else { throw WorkspaceBrowserError.denied }
        let attachment = attachments[id]
        let ownsTab = tab.scope == command.scope && !tab.stopped
        let controlsTab = attachment?.scope == command.scope && attachment?.origin == origin
        switch command.name {
        case "browser_attach":
            guard id == selectedID, tab.scope == nil, attachment == nil || controlsTab else { throw WorkspaceBrowserError.denied }
        case "browser_snapshot":
            guard ownsTab || controlsTab || (tab.scope == nil && (id == selectedID || command.origins.contains("*"))) else { throw WorkspaceBrowserError.denied }
        case "browser_close":
            guard ownsTab else { throw WorkspaceBrowserError.denied }
        default:
            guard ownsTab || controlsTab else { throw WorkspaceBrowserError.denied }
        }
        return tab
    }
    private func state(_ tab: BrowserTab) -> ChatJSON {
        .object(["tab_id": .string(tab.id.uuidString), "document_id": .string(tab.documentID.uuidString), "url": .string(tab.url?.absoluteString ?? ""), "title": .string(tab.title), "state": .string(tab.loading ? "loading" : "ready")])
    }
}
