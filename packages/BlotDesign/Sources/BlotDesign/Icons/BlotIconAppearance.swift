#if os(iOS)
import UIKit

@MainActor
public enum BlotIconAppearance {
    public static func configureNavigation() {
        let image = UIImage(named: BlotGlyph.chevronLeft.assetName, in: .module, compatibleWith: nil)?
            .withRenderingMode(.alwaysTemplate)
        UINavigationBar.appearance().backIndicatorImage = image
        UINavigationBar.appearance().backIndicatorTransitionMaskImage = image
    }
}
#endif
