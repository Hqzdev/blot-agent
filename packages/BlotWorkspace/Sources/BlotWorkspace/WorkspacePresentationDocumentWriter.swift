import CoreGraphics
import CoreText
import Foundation

/// Creates an offline 16:9 PDF deck; every supplied slide becomes one complete page.
public struct WorkspacePresentationDocumentWriter: Sendable {
    public struct Slide: Codable, Sendable {
        public let title: String
        public let body: String
        public init(title: String, body: String) { self.title = title; self.body = body }
    }
    public init() {}
    public func pdf(slides: [Slide]) throws -> Data {
        guard (1...30).contains(slides.count), slides.allSatisfy({
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.utf8.count <= 1000
                && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.body.utf8.count <= 10_000
        }) else { throw WorkspaceStorageError.invalidParameters }
        let output = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 960, height: 540)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw WorkspaceFileError.unreadablePDF }
        do {
            for (index, slide) in slides.enumerated() {
                context.beginPDFPage(nil)
                context.setFillColor(CGColor(gray: 0.96, alpha: 1)); context.fill(page)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.addPath(CGPath(roundedRect: page.insetBy(dx: 18, dy: 18), cornerWidth: 24, cornerHeight: 24, transform: nil)); context.fillPath()
                context.setFillColor(CGColor(red: 0.94, green: 0.12, blue: 0.25, alpha: 1)); context.fill(CGRect(x: 54, y: 390, width: 64, height: 4))
                try draw(slide.title, in: CGRect(x: 54, y: 408, width: 852, height: 80), font: "Helvetica-Bold", sizes: [34, 30, 26, 22, 18], context: context)
                try draw(slide.body, in: CGRect(x: 54, y: 76, width: 852, height: 292), font: "Helvetica", sizes: [24, 22, 20, 18, 16, 14, 12], context: context)
                try draw("\(index + 1) / \(slides.count)", in: CGRect(x: 840, y: 36, width: 66, height: 20), font: "Helvetica", sizes: [11], context: context)
                context.endPDFPage()
            }
            context.closePDF()
            return output as Data
        } catch { context.endPDFPage(); context.closePDF(); throw error }
    }
    private func draw(_ text: String, in rect: CGRect, font: String, sizes: [CGFloat], context: CGContext) throws {
        for size in sizes {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)
            ])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
            if CTFrameGetVisibleStringRange(frame).length == attributed.length {
                context.textMatrix = .identity; CTFrameDraw(frame, context); return
            }
        }
        // Never silently clip a title or slide body.
        throw WorkspaceStorageError.invalidParameters
    }
}
