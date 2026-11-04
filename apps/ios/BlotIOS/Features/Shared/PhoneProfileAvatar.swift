import BlotDesign
import Foundation
import SwiftUI
import UIKit

struct PhoneProfileAvatar: View {
    let data: Data?
    var size: CGFloat = 72
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(WorkspaceStyle.secondary.opacity(0.1))
                    .overlay { BlotIcon(.person, size: size * 0.46).foregroundStyle(WorkspaceStyle.secondary) }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: data) {
            guard let data else { image = nil; return }
            let pixels = max(1, Int(size * displayScale))
            let thumbnail = await Task.detached(priority: .userInitiated) {
                PhoneAvatarImage.thumbnail(data, pixels: pixels)
            }.value
            guard !Task.isCancelled else { return }
            image = thumbnail.map { UIImage(cgImage: $0) }
        }
        .accessibilityHidden(true)
    }
}
