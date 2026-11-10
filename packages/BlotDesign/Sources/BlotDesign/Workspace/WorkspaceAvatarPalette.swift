import SwiftUI

public enum WorkspaceAvatarPalette {
    public static func color(_ key: String) -> Color {
        switch key {
        case "white": .white
        case "brown": Color(red: 0.55, green: 0.35, blue: 0.18)
        case "red": Color(red: 1, green: 0.13, blue: 0.24)
        case "blue": Color(red: 0.06, green: 0.49, blue: 1)
        case "pink": Color(red: 1, green: 0.13, blue: 0.60)
        case "orange": Color(red: 1, green: 0.37, blue: 0)
        case "green": Color(red: 0, green: 0.78, blue: 0.40)
        case "amber": Color(red: 1, green: 0.61, blue: 0)
        case "gray": Color(white: 0.48)
        case "purple": Color(red: 0.70, green: 0.57, blue: 0.91)
        case "teal": Color(red: 0.29, green: 0.71, blue: 0.64)
        default:
            if key.count == 7, key.first == "#", let value = UInt32(key.dropFirst(), radix: 16) {
                Color(red: Double((value >> 16) & 255) / 255,
                      green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
            } else { Color.primary }
        }
    }
}
