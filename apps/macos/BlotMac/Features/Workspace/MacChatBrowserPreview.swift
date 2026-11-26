import AppKit
import BlotAppleIntegrations
import BlotDesign
import SwiftUI
import WebKit

/// A read-only browser thumbnail; the live web view remains attached to its browser surface.
struct MacChatBrowserPreview: View {
    var tabID: UUID? = nil
    var height: CGFloat = 145
    @Environment(WorkspaceStore.self) private var store
    @State private var image: NSImage?
    private var tab: BrowserTab? {
        guard let browser = store.browser else { return nil }
        if let tabID { return browser.tabs.first { $0.id == tabID } }
        return browser.selectedTab
    }
    var body: some View {
        ZStack {
            MacChatStyle.incoming
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else {
                VStack(spacing: 8) {
                    BlotIcon(symbol: "desktopcomputer", size: 25).foregroundStyle(.secondary)
                    Text(tab?.error ?? (store.language == "ru" ? (tab == nil ? "Браузер ещё не открыт" : "Открыть браузер") : (tab == nil ? "Browser hasn't been opened" : "Open browser")))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 18))
            .task(id: "\(tab?.id.uuidString ?? ""):\(tab?.documentID.uuidString ?? ""):\(tab?.loading ?? false):\(tab?.error ?? "")") {
                image = nil
                guard let tab, !tab.loading, tab.error == nil, let view = store.browser?.webView(for: tab.id), !view.bounds.isEmpty else { return }
                let configuration = WKSnapshotConfiguration(); configuration.snapshotWidth = 600
                image = try? await view.takeSnapshot(configuration: configuration)
            }
            .accessibilityLabel(store.language == "ru" ? "Предпросмотр браузера" : "Browser preview")
    }
}
