import SwiftUI

struct MacTeamFileIcon: View {
    let filename: String
    var size: CGFloat = 28

    var body: some View {
        Image(MacTeamFileKind(filename: filename).assetName)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
