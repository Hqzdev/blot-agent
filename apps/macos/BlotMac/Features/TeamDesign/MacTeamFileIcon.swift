import BlotDesign
import SwiftUI

struct MacTeamFileIcon: View {
    let filename: String
    var size: CGFloat = 28

    var body: some View {
        BlotIcon(MacTeamFileKind(filename: filename).glyph, size: size)
    }
}
