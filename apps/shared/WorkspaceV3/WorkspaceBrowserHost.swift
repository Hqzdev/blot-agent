import BlotAppleIntegrations
import SwiftUI

struct WorkspaceBrowserHost: ViewModifier {
    @Environment(WorkspaceStore.self) private var store
    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { store.openBrowserURL(url); return .handled }
            if ["app-settings", "x-apple.systempreferences", "blot-agent-macos", "blot-agent-ios"].contains(url.scheme ?? "") { return .systemAction }
            store.error = store.language == "ru" ? "Эта ссылка не открывает внешнее приложение автоматически." : "This link does not open an external app automatically."
            return .discarded
        })
        #if os(iOS)
        .sheet(isPresented: Binding(get: { store.browser?.presented == true && store.route != .browser }, set: { store.browser?.presented = $0 })) {
            if let browser = store.browser { WorkspaceBrowserView(controller: browser).environment(store) }
        }
        #else
        .sheet(isPresented: Binding(get: { store.browser?.presented == true && (store.snapshot.ownerID == nil || store.route.isAuthentication) && store.route != .browser }, set: { store.browser?.presented = $0 })) {
            if let browser = store.browser { WorkspaceBrowserView(controller: browser).environment(store).frame(minWidth: 720, minHeight: 540) }
        }
        #endif
    }
}
