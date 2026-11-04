import BlotAppleIntegrations
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ApplePluginIcon: View {
    let plugin: ApplePluginID
    var size: CGFloat = 36
    var body: some View {
        Group {
            #if os(macOS)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: plugin.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
            } else { Image(plugin.asset).resizable().scaledToFit() }
            #else
            Image(plugin.asset).resizable().scaledToFit()
            #endif
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
