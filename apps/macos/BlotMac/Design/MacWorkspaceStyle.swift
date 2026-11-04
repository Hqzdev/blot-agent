import BlotDesign
import SwiftUI

enum MacWorkspaceStyle {
    static let sidebarWidth: CGFloat = 300
    static let inspectorWidth: CGFloat = 340
    static let composerWidth: CGFloat = 620
    static let readingWidth: CGFloat = 660
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let sidebar = BlotColor.dynamic(.init(light: 0xF6F6F6FF, dark: 0x161616FF))
    static let edge = BlotColor.dynamic(.init(light: 0x00000010, dark: 0xFFFFFF0D))
}
