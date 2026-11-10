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
            if let image = ApplePluginIconCache.image(for: plugin) {
                Image(nsImage: image).resizable().scaledToFit()
            } else { Image(plugin.asset).resizable().scaledToFit() }
            #else
            Image(plugin.asset).resizable().scaledToFit()
            #endif
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

#if os(macOS)
@MainActor
private enum ApplePluginIconCache {
    private final class Value {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }
    private static let cache: NSCache<NSString, Value> = {
        let cache = NSCache<NSString, Value>(); cache.countLimit = 32; cache.totalCostLimit = 8 * 1024 * 1024; return cache
    }()
    static func image(for plugin: ApplePluginID) -> NSImage? {
        let key = plugin.bundleID as NSString
        if let cached = cache.object(forKey: key) { return cached.image }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: plugin.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache.setObject(Value(image), forKey: key, cost: image == nil ? 128 : 1024 * 1024)
        return image
    }
}
#endif
