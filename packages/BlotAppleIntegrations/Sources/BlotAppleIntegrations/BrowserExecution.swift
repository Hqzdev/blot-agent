import BlotWorkspace
import Foundation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension WorkspaceBrowserController {
    public func prepare(_ command: WorkspaceBrowserCommand) async throws -> WorkspaceBrowserBinding {
        guard !stopped, WorkspaceBrowserCatalog.toolIDs.contains(command.name) else { throw WorkspaceBrowserError.unavailable }
        let arguments = try AppleArguments(command.arguments)
        if command.name == "browser_tabs" { return .init(tabID: command.id, documentID: command.id, url: "") }
        if command.name == "browser_open" {
            let url = try WorkspaceBrowserURL.validated(arguments.required("url"))
            let origin = try WorkspaceBrowserURL.origin(url)
            guard command.origins.contains("*") || command.origins.contains(origin) else { throw WorkspaceBrowserError.denied }
            if let tab = tabs.first(where: { $0.id == command.id }) {
                guard tab.scope == command.scope, tab.initialURL == url, !tab.stopped else { throw WorkspaceBrowserError.denied }
                return .init(tabID: tab.id, documentID: tab.documentID, url: url.absoluteString)
            }
            return .init(tabID: command.id, documentID: command.id, url: url.absoluteString)
        }
        let tab = try ownedTab(arguments, command: command)
        if pages[tab.id] == nil, command.name == "browser_snapshot", command.origins.contains("*") {
            try select(tab.id); try await pages[tab.id]?.waitForLoad()
        }
        guard pages[tab.id] != nil, !tab.loading, let url = tab.url else { throw WorkspaceBrowserError.stalePage }
        if WorkspaceBrowserCatalog.requiresConfirmation(command.name) {
            guard arguments["document_id"] == tab.documentID.uuidString, let page = pages[tab.id], !busyTabs.contains(tab.id) else { throw WorkspaceBrowserError.stalePage }
            let element = try arguments.required("element_id")
            let value = try await page.script(BrowserDOM.target, arguments: ["element": element])
            guard case .string(let target) = value, target.utf8.count < 4096 else { throw WorkspaceBrowserError.stalePage }
            return .init(tabID: tab.id, documentID: tab.documentID, url: url.absoluteString, target: target, interactionRevision: tab.interactionRevision)
        }
        return .init(tabID: tab.id, documentID: tab.documentID, url: url.absoluteString, interactionRevision: tab.interactionRevision)
    }
    public func execute(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserResult {
        guard !stopped else { throw WorkspaceBrowserError.unavailable }
        let arguments = try AppleArguments(command.arguments)
        if command.name == "browser_tabs" {
            guard try await prepare(command) == binding else { throw WorkspaceBrowserError.stalePage }
            let visible = tabs.filter { tab in
                guard let url = tab.url, let origin = try? WorkspaceBrowserURL.origin(url), command.origins.contains("*") || command.origins.contains(origin) else { return false }
                return tab.scope == nil || tab.scope == command.scope || (command.origins.contains("*") && selectedID == tab.id)
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
                tab = BrowserTab(id: binding.tabID, url: URL(string: binding.url), scope: command.scope, origins: command.origins)
                try createPage(tab); tabsAppend(tab); pages[tab.id]?.load(URL(string: binding.url)!)
            }
            guard let page = pages[tab.id] else { throw WorkspaceBrowserError.stalePage }
            busyTabs.insert(tab.id); defer { busyTabs.remove(tab.id) }
            try await page.waitForLoad(); return .value(state(tab))
        }
        let tab = try ownedTab(arguments, command: command)
        guard tab.id == binding.tabID, tab.documentID == binding.documentID, tab.url?.absoluteString == binding.url,
              tab.interactionRevision == binding.interactionRevision,
              let page = pages[tab.id], busyTabs.insert(tab.id).inserted else { throw WorkspaceBrowserError.stalePage }
        defer { busyTabs.remove(tab.id) }
        switch command.name {
        case "browser_snapshot":
            let value = try await page.script(BrowserDOM.snapshot)
            guard case .object(var fields) = value, tab.documentID == binding.documentID,
                  tab.scope != nil || selectedID == tab.id || command.origins.contains("*") else { throw WorkspaceBrowserError.stalePage }
            fields["tab_id"] = .string(tab.id.uuidString); fields["document_id"] = .string(tab.documentID.uuidString)
            fields["url"] = .string(binding.url); fields["title"] = .string(tab.title)
            fields["read_only_user_tab"] = .bool(tab.scope != command.scope)
            return .value(.object(fields))
        case "browser_click", "browser_type":
            guard (arguments["text"] ?? "").utf8.count <= 8192 else { throw WorkspaceBrowserError.denied }
            if command.name == "browser_click" { page.view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true }
            defer { page.view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = false }
            let result = try await page.script(BrowserDOM.action, arguments: ["element": try arguments.required("element_id"), "expected": binding.target, "kind": command.name, "text": arguments["text"] ?? ""])
            if case .object(var fields) = result {
                fields["tabs"] = .array(tabs.filter { $0.scope == command.scope }.map(state))
                return .value(.object(fields))
            }
            return .value(result)
        case "browser_scroll": return .value(try await page.script(BrowserDOM.scroll, arguments: ["direction": arguments["direction"] ?? "down"]))
        case "browser_back": try back(tab.id); try await page.waitForLoad(); return .value(state(tab))
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
    private func ownedTab(_ arguments: AppleArguments, command: WorkspaceBrowserCommand) throws -> BrowserTab {
        let id: UUID?
        if let raw = arguments["tab_id"] { id = UUID(uuidString: raw) }
        else { id = command.name == "browser_snapshot" ? selectedID : nil }
        let automaticRead = command.name == "browser_snapshot" && command.origins.contains("*")
        guard let id, let tab = tabs.first(where: { $0.id == id }),
              (tab.scope == command.scope || (tab.scope == nil && (selectedID == id || automaticRead) && command.name == "browser_snapshot") || (selectedID == id && automaticRead)),
              (!tab.stopped || automaticRead), let url = tab.url,
              (try command.origins.contains("*") || command.origins.contains(WorkspaceBrowserURL.origin(url))) else { throw WorkspaceBrowserError.denied }
        return tab
    }
    private func state(_ tab: BrowserTab) -> ChatJSON {
        .object(["tab_id": .string(tab.id.uuidString), "document_id": .string(tab.documentID.uuidString), "url": .string(tab.url?.absoluteString ?? ""), "title": .string(tab.title), "state": .string(tab.loading ? "loading" : "ready")])
    }
}
