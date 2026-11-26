import BlotDesign
import BlotDomain
import Foundation
import SwiftUI

/// Message color follows the direct-chat agent; group conversations use a neutral accent.
enum WorkspaceChatStyle {
    static let avatarBaseline = VerticalAlignment(AvatarAlignment.self)

    static func outgoing(agent: BlotV3.AgentProfile?, group: Bool, environment: EnvironmentValues) -> Color {
        guard !group, let agent else { return Color(white: 0.065) }
        var paletteEnvironment = environment
        paletteEnvironment.colorScheme = .light
        let color = WorkspaceAvatarPalette.color(agent.avatarColor).resolve(in: paletteEnvironment)
        let red = Double(color.red), green = Double(color.green), blue = Double(color.blue)
        var shade = 0.82
        while contrast(red * shade, green * shade, blue * shade) < 4.5 { shade -= 0.02 }
        return Color(red: red * shade, green: green * shade, blue: blue * shade)
    }

    private static func contrast(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 1.05 / (0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue) + 0.05)
    }

    private struct AvatarAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.bottom] }
    }
}
