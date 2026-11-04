import CoreGraphics
import CoreText
import Foundation

public struct WorkspaceDocumentWriter: Sendable {
    public init() {}

    public func markdown(title: String, body: String) -> Data { Data(("# " + title + "\n\n" + body + "\n").utf8) }

    public func csv(headers: [String], rows: [[String]]) throws -> Data {
        guard !headers.isEmpty, rows.allSatisfy({ $0.count == headers.count }) else { throw WorkspaceStorageError.invalidParameters }
        func cell(_ text: String) -> String {
            let value = text.first.map { "=+-@".contains($0) } == true ? "'" + text : text
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return Data(([headers] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n").appending("\r\n").utf8)
    }

    public func pdf(title: String, body: String) throws -> Data {
        guard title.count + body.count <= 500_000 else { throw WorkspaceFileError.tooLarge }
        let output = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw WorkspaceFileError.unreadablePDF
        }
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let text = NSMutableAttributedString(string: title + "\n\n" + body,
            attributes: [fontKey: CTFontCreateWithName("Helvetica" as CFString, 12, nil)])
        text.addAttribute(fontKey, value: CTFontCreateWithName("Helvetica-Bold" as CFString, 20, nil),
            range: NSRange(location: 0, length: title.utf16.count))
        let setter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let path = CGPath(rect: page.insetBy(dx: 48, dy: 48), transform: nil)
        var position = 0
        while position < text.length {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: position, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                context.endPDFPage(); context.closePDF()
                throw WorkspaceFileError.unreadablePDF
            }
            CTFrameDraw(frame, context)
            context.endPDFPage()
            position += visible.length
        }
        context.closePDF()
        return output as Data
    }
}
