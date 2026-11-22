import SwiftUI

struct WorkspaceMenuGap: View {
    var body: some View {
        #if os(macOS)
        Color.clear.frame(height: 4).accessibilityHidden(true).allowsHitTesting(false)
        #else
        Divider()
        #endif
    }
}
