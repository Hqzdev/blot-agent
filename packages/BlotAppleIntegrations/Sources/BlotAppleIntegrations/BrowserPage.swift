import BlotWorkspace
import Foundation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class BrowserPage: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "dev.blot.browser")
    let tab: BrowserTab
    let view: WKWebView
    weak var owner: WorkspaceBrowserController?
    private var observations: [NSKeyValueObservation] = []
    private var loads: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var scripts: [UUID: CheckedContinuation<ChatJSON, Error>] = [:]
    private var images: [UUID: CheckedContinuation<Data, Error>] = [:]
    private var timers: [UUID: Task<Void, Never>] = [:]
    init(tab: BrowserTab, owner: WorkspaceBrowserController, dataStore: WKWebsiteDataStore) {
        self.tab = tab; self.owner = owner
        let config = WKWebViewConfiguration(); config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.addUserScript(WKUserScript(source: BrowserDOM.bootstrap, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: Self.world))
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 720), configuration: config)
        super.init()
        config.userContentController.add(self, contentWorld: Self.world, name: "blotDirty")
        view.navigationDelegate = self; view.uiDelegate = self
        observations = [view.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
                        view.observe(\.title, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
                        view.observe(\.url, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
                        view.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
                        view.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in Task { @MainActor in self?.refresh() } }]
    }
    func load(_ url: URL) { tab.error = nil; tab.authenticationURL = nil; tab.loading = true; view.load(URLRequest(url: url)) }
    func refresh() {
        if let url = view.url, (try? WorkspaceBrowserURL.validated(url.absoluteString)) != nil { tab.url = url }
        tab.progress = view.estimatedProgress; tab.title = view.title?.isEmpty == false ? view.title! : tab.url?.host ?? "Новая вкладка"
        tab.canGoBack = view.canGoBack; tab.canGoForward = view.canGoForward
    }
    func snapshot() async throws -> Data {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            images[id] = continuation
            let configuration = WKSnapshotConfiguration()
            let width = max(1, min(1000, view.bounds.width))
            configuration.rect = CGRect(x: view.bounds.minX, y: view.bounds.minY, width: view.bounds.width, height: min(view.bounds.height, 2_000_000 / width))
            configuration.snapshotWidth = NSNumber(value: Double(width))
            view.takeSnapshot(with: configuration) { [weak self] image, error in
                guard let self, let reply = self.images.removeValue(forKey: id) else { return }
                self.timers.removeValue(forKey: id)?.cancel()
                #if os(macOS)
                let data = image?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
                #else
                let data = image?.pngData()
                #endif
                if let data { reply.resume(returning: data) } else { reply.resume(throwing: WorkspaceBrowserError.unavailable) }
            }
            timers[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(8)); self?.images.removeValue(forKey: id)?.resume(throwing: WorkspaceBrowserError.timeout); self?.timers.removeValue(forKey: id) } catch {}
            }
        }
    }
    func waitForLoad() async throws {
        guard tab.loading || view.isLoading else { if tab.error != nil { throw WorkspaceBrowserError.unavailable }; return }
        let id = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loads[id] = continuation
            timers[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)); self?.finishLoad(id, error: WorkspaceBrowserError.timeout) } catch {}
            }
        }
    }
    func script(_ script: String, arguments: [String: Any] = [:]) async throws -> ChatJSON {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            scripts[id] = continuation
            view.callAsyncJavaScript(BrowserDOM.bootstrap + "\n" + script, arguments: arguments, in: nil, in: Self.world) { [weak self] result in
                guard let self, let continuation = self.scripts.removeValue(forKey: id) else { return }
                self.timers.removeValue(forKey: id)?.cancel()
                switch result {
                case .success(let value):
                    do {
                        let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
                        continuation.resume(returning: try JSONDecoder().decode(ChatJSON.self, from: data))
                    } catch { continuation.resume(throwing: WorkspaceBrowserError.unknown) }
                case .failure(let error):
                    let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
                    continuation.resume(throwing: message.contains("stale_or_manual") || message.contains("manual_field") ? WorkspaceBrowserError.stalePage : WorkspaceBrowserError.unknown)
                }
            }
            timers[id] = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(8))
                    self?.scripts.removeValue(forKey: id)?.resume(throwing: WorkspaceBrowserError.timeout); self?.timers.removeValue(forKey: id)
                } catch {}
            }
        }
    }
    func stop() {
        view.stopLoading(); tab.loading = false
        for timer in timers.values { timer.cancel() }; timers.removeAll()
        let waiting = loads.values; loads.removeAll(); for item in waiting { item.resume(throwing: WorkspaceBrowserError.canceled) }
        let running = scripts.values; scripts.removeAll(); for item in running { item.resume(throwing: WorkspaceBrowserError.canceled) }
        let snapshots = images.values; images.removeAll(); for item in snapshots { item.resume(throwing: WorkspaceBrowserError.canceled) }
    }
    func detach() {
        stop(); observations.removeAll()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "blotDirty", contentWorld: Self.world)
        view.navigationDelegate = nil; view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }
    private func finishLoad(_ id: UUID, error: Error? = nil) {
        timers.removeValue(forKey: id)?.cancel()
        guard let item = loads.removeValue(forKey: id) else { return }
        if let error { item.resume(throwing: error) } else { item.resume() }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab.documentID = UUID(); tab.loading = true; tab.error = nil
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab.url = webView.url; tab.unsaved = false; tab.sensitiveInput = false; refresh()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab.loading = false; refresh(); owner?.saveTabs()
        for id in Array(loads.keys) { finishLoad(id) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        tab.loading = false
        if (error as NSError).code != NSURLErrorCancelled { tab.error = "Не удалось загрузить страницу." }
        for id in Array(loads.keys) { finishLoad(id, error: WorkspaceBrowserError.unavailable) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        stop(); tab.documentID = UUID(); tab.error = "Процесс сайта завершился. Обновите страницу вручную; действие агента не повторяется."
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        if navigationAction.shouldPerformDownload, url.scheme == "blob",
           let source = URL(string: String(url.absoluteString.dropFirst(5))), owner?.permits(source, tab: tab) == true { decisionHandler(.download); return }
        guard (try? WorkspaceBrowserURL.validated(url.absoluteString)) != nil else {
            tab.error = "Эта ссылка не открывается во внешнем приложении автоматически."; decisionHandler(.cancel); return
        }
        if navigationAction.targetFrame?.isMainFrame != false {
            if WorkspaceBrowserURL.isRestrictedAuthentication(url) { tab.authenticationURL = url; tab.loading = false; tab.error = WorkspaceBrowserError.manualSignIn.localizedDescription; decisionHandler(.cancel); return }
            guard owner?.permits(url, tab: tab) == true, !tab.stopped else { tab.error = WorkspaceBrowserError.denied.localizedDescription; decisionHandler(.cancel); return }
            if tab.unsaved && navigationAction.navigationType != .formSubmitted && navigationAction.navigationType != .formResubmitted {
                tab.error = WorkspaceBrowserError.unsavedChanges.localizedDescription; decisionHandler(.cancel); return
            }
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, let owner, owner.permits(url, tab: tab) else { return nil }
        do {
            let child = BrowserTab(url: url, scope: tab.scope, origins: tab.allowedOrigins, sessionKey: tab.sessionKey)
            try owner.createPage(child); owner.tabsAppend(child); owner.pages[child.id]?.load(url)
        } catch { tab.error = error.localizedDescription }
        return nil
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { downloading(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { downloading(download) }
    private func downloading(_ download: WKDownload) {
        tab.loading = false
        owner?.beginDownload(download, tabID: tab.id)
        for id in Array(loads.keys) { finishLoad(id) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "blotDirty" else { return }
        if let dirty = message.body as? Bool, dirty { tab.unsaved = true; tab.interactionRevision += 1 }
        if let fields = message.body as? [String: Bool], fields["sensitive"] == true { tab.sensitiveInput = true }
    }
    #if os(macOS)
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection; panel.canChooseDirectories = parameters.allowsDirectories
        guard let window = webView.window else { completionHandler(nil); return }
        panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }
    #endif
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}
