import BlotDesign
import SwiftUI

struct DiffView: View {
    let file: ReviewFile
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                KIcon("file-text", size: 14, color: K.text3).accessibilityHidden(true)
                Text(file.path).font(KFont.mono(12)).foregroundStyle(K.text).lineLimit(1).truncationMode(.middle)
                Text("+\(file.added)").foregroundStyle(K.success).accessibilityLabel("\(file.added) lines added")
                Text("−\(file.removed)").foregroundStyle(K.danger).accessibilityLabel("\(file.removed) lines removed")
                Spacer()
                CopyButton(text: file.patch, title: "Copy patch").fixedSize()
            }.font(KFont.mono(12)).padding(.leading, 12).padding(.trailing, 4).frame(height: 40).kBorder(.bottom)
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(file.lines) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.oldNumber.map(String.init) ?? "").foregroundStyle(K.text3).frame(width: 25, alignment: .trailing)
                            Text(line.newNumber.map(String.init) ?? "").foregroundStyle(K.text3).frame(width: 25, alignment: .trailing)
                            Text(symbol(line.tone)).foregroundStyle(color(line.tone)).frame(width: 12)
                            Text(line.text.isEmpty ? " " : line.text)
                                .foregroundStyle(line.tone == .header ? K.text3 : K.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 12)
                        }
                        .font(KFont.mono(12)).padding(.horizontal, 8).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading).background(background(line.tone))
                    }
                }.frame(minWidth: 500, alignment: .leading)
            }
        }.kCard(radius: K.rLg, fill: K.bg)
    }
    private func symbol(_ tone: DiffTone) -> String {
        switch tone { case .added: "+"; case .removed: "−"; default: " " }
    }
    private func color(_ tone: DiffTone) -> Color {
        switch tone { case .added: K.success; case .removed: K.danger; default: K.text3 }
    }
    private func background(_ tone: DiffTone) -> Color {
        switch tone { case .added: K.diffAddBg; case .removed: K.diffDelBg; case .header: K.surface2; default: .clear }
    }
}
