import BlotDesign
import BlotDomain
import Foundation
import SwiftUI

struct PhoneFileRow: View {
    let file: BlotV3.Artifact

    private var kind: PhoneFileKind { PhoneFileKind(name: file.name, mediaType: file.mediaType) }
    private var details: String {
        let fileExtension = (file.name as NSString).pathExtension.uppercased()
        let size = ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)
        return fileExtension.isEmpty ? size : "\(fileExtension) · \(size)"
    }

    var body: some View {
        HStack(spacing: 14) {
            BlotIcon(symbol: kind.symbol, size: 24).font(.system(size: 21, weight: .medium))
                .foregroundStyle(kind.color).frame(width: 42, height: 44)
                .background(kind.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.body).foregroundStyle(WorkspaceStyle.ink).lineLimit(2)
                Text(details).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .multilineTextAlignment(.leading).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
