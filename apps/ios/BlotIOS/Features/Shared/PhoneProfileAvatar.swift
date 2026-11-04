import BlotDesign
import Foundation
import SwiftUI
import UIKit

struct PhoneProfileAvatar: View {
    let data: Data?
    var size: CGFloat = 72
    @State private var image: UIImage?

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
        .task(id: data) { image = data.flatMap { UIImage(data: $0) } }
        .accessibilityHidden(true)
    }
}
