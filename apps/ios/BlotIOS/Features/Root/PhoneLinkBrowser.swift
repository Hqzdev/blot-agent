import SafariServices
import UIKit

@MainActor
enum PhoneLinkBrowser {
    private static weak var presentedBrowser: SFSafariViewController?

    static func open(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive && $0.keyWindow != nil }),
              var presenter = scene.keyWindow?.rootViewController else { return false }
        while let next = presenter.presentedViewController { presenter = next }
        guard !(presenter is SFSafariViewController), !presenter.isBeingDismissed else { return false }
        let browser = SFSafariViewController(url: url)
        browser.modalPresentationStyle = .pageSheet
        presentedBrowser = browser
        presenter.present(browser, animated: true)
        return true
    }

    static func dismiss() {
        presentedBrowser?.dismiss(animated: true)
    }
}
