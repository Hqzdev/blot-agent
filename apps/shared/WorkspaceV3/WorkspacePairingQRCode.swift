import CoreImage.CIFilterBuiltins
import SwiftUI

struct WorkspacePairingQRCode: View {
    let value: String
    var resourceBundle: Bundle = .main

    var body: some View {
        if let image = Self.image(for: value, resourceBundle: resourceBundle) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                .padding(16).background(.white, in: .rect(cornerRadius: 20))
                .frame(width: 260, height: 260)
                .accessibilityLabel("QR code").accessibilityIdentifier("pairing.qr")
        }
    }

    static func image(for value: String, resourceBundle: Bundle = .main) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let qr = CIContext().createCGImage(scaled, from: scaled.extent),
              let context = CGContext(data: nil, width: qr.width, height: qr.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: qr.width, height: qr.height)
        context.interpolationQuality = .none
        context.draw(qr, in: bounds)

        let badgeSide = floor(bounds.width * 0.17 / 6) * 6
        let badge = Image("BlotPairingMark", bundle: resourceBundle).renderingMode(.template)
            .resizable().scaledToFit().foregroundStyle(.black)
            .padding(badgeSide * 0.06).frame(width: badgeSide, height: badgeSide)
            .background(.white, in: .rect(cornerRadius: badgeSide * 0.2))
        guard let logo = ImageRenderer(content: badge).cgImage else { return nil }
        context.draw(logo, in: CGRect(x: bounds.midX - badgeSide / 2,
            y: bounds.midY - badgeSide / 2, width: badgeSide, height: badgeSide))
        return context.makeImage()
    }
}
