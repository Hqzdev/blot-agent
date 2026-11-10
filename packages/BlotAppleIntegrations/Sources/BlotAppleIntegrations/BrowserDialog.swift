import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class BrowserDialog: Identifiable {
    public enum Kind { case alert, confirmation, prompt }
    public let id = UUID()
    public let kind: Kind
    public let message: String
    public let origin: String
    public var input: String
    @ObservationIgnored private var reply: ((String?) -> Void)?
    init(kind: Kind, message: String, origin: String, input: String = "", reply: @escaping (String?) -> Void) {
        self.kind = kind; self.message = String(message.prefix(2000)); self.origin = origin; self.input = input; self.reply = reply
    }
    public func finish(accepted: Bool) { let callback = reply; reply = nil; callback?(accepted ? input : nil) }
}

extension BrowserPage {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        guard let owner, owner.dialog == nil else { completionHandler(); return }
        owner.dialog = BrowserDialog(kind: .alert, message: message, origin: frame.securityOrigin.host) { [weak owner] _ in owner?.dialog = nil; completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let owner, owner.dialog == nil else { completionHandler(false); return }
        owner.dialog = BrowserDialog(kind: .confirmation, message: message, origin: frame.securityOrigin.host) { [weak owner] value in owner?.dialog = nil; completionHandler(value != nil) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        guard let owner, owner.dialog == nil else { completionHandler(nil); return }
        owner.dialog = BrowserDialog(kind: .prompt, message: prompt, origin: frame.securityOrigin.host, input: defaultText ?? "") { [weak owner] value in owner?.dialog = nil; completionHandler(value) }
    }
}
