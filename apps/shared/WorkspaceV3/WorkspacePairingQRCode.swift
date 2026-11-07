import CoreImage.CIFilterBuiltins
import SwiftUI

struct WorkspacePairingQRCode: View {
    let value: String

    var body: some View {
        if let image = Self.image(for: value) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                .padding(16).background(.white, in: .rect(cornerRadius: 20))
                .frame(width: 260, height: 260)
                .accessibilityLabel("QR code").accessibilityIdentifier("pairing.qr")
        }
    }

    static func image(for value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
