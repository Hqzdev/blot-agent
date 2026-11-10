import CoreGraphics
import Foundation
import ImageIO
import PDFKit

public struct WorkspaceExtractedText: Codable, Equatable, Sendable {
    public let content: String
    public let startPage: Int
    public let totalPages: Int
    public let nextPage: Int?
    public let usedOCR: Bool
    public let truncated: Bool
    public func limited(to maximumCharacters: Int) throws -> Self {
        guard (1...48_000).contains(maximumCharacters) else { throw WorkspaceStorageError.invalidParameters }
        return .init(content: String(content.prefix(maximumCharacters)), startPage: startPage, totalPages: totalPages,
            nextPage: nextPage, usedOCR: usedOCR, truncated: truncated || content.count > maximumCharacters)
    }
}

/// Parses text and rasterizes only pages without a text layer. A read covers at most 20 pages.
public struct WorkspaceFileTextExtractor: Sendable {
    private let recognizer: any WorkspaceTextRecognizing
    public init(recognizer: any WorkspaceTextRecognizing = WorkspaceVisionTextRecognizer()) { self.recognizer = recognizer }

    public func validate(_ data: Data, mediaType: String) throws {
        if WorkspaceFileFormat.isText(mediaType) {
            guard String(data: data, encoding: .utf8) != nil else { throw WorkspaceFileError.invalidText }
        } else if mediaType == "application/pdf" { _ = try pdf(data) }
        else if mediaType.hasPrefix("image/") { _ = try imageSource(data) }
        else { throw WorkspaceFileError.unsupportedType }
    }

    public func extract(_ data: Data, mediaType: String, startPage: Int = 1, pageCount: Int = 20) throws -> WorkspaceExtractedText {
        guard (1...1_000).contains(startPage), (1...20).contains(pageCount) else { throw WorkspaceStorageError.invalidParameters }
        try _Concurrency.Task.checkCancellation()
        if WorkspaceFileFormat.isText(mediaType) {
            guard startPage == 1, let text = String(data: data, encoding: .utf8) else { throw WorkspaceFileError.invalidText }
            return .init(content: String(text.prefix(48_000)), startPage: 1, totalPages: 1, nextPage: nil, usedOCR: false, truncated: text.count > 48_000)
        }
        var content = "", usedOCR = false, truncated = false
        let total: Int
        let readPage: (Int) throws -> String
        if mediaType == "application/pdf" {
            let document = try pdf(data)
            guard let provider = CGDataProvider(data: data as CFData), let rasterDocument = CGPDFDocument(provider) else { throw WorkspaceFileError.unreadablePDF }
            total = document.pageCount
            readPage = { index in
                guard let page = document.page(at: index) else { throw WorkspaceFileError.unreadablePDF }
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty { return text }
                guard let rasterPage = rasterDocument.page(at: index + 1) else { throw WorkspaceFileError.unreadablePDF }
                usedOCR = true
                return try recognizer.recognize(render(rasterPage), orientation: .up)
            }
        } else if mediaType.hasPrefix("image/") {
            let source = try imageSource(data)
            total = CGImageSourceGetCount(source)
            readPage = { index in
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 3_000,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { throw WorkspaceFileError.unreadableImage }
                usedOCR = true
                return try recognizer.recognize(image, orientation: .up)
            }
        } else { throw WorkspaceFileError.unsupportedType }
        guard startPage <= total else { throw WorkspaceStorageError.invalidParameters }
        let end = min(total, startPage - 1 + pageCount)
        var nextPage: Int?, hasText = false
        for index in (startPage - 1)..<end {
            try _Concurrency.Task.checkCancellation()
            let text = try autoreleasepool { try readPage(index) }
            hasText = hasText || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let entry = "[Page \(index + 1)]\n" + text + "\n"
            let remaining = 48_000 - content.count
            content += entry.prefix(remaining)
            nextPage = index + 1 < total ? index + 2 : nil
            if entry.count > remaining { truncated = true; break }
        }
        try _Concurrency.Task.checkCancellation()
        guard hasText else { throw WorkspaceFileError.noRecognizableText }
        return .init(content: content, startPage: startPage, totalPages: total, nextPage: nextPage,
            usedOCR: usedOCR, truncated: truncated || nextPage != nil)
    }

    private func pdf(_ data: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: data), !document.isLocked, (1...1_000).contains(document.pageCount) else { throw WorkspaceFileError.unreadablePDF }
        return document
    }
    private func imageSource(_ data: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              (1...1_000).contains(CGImageSourceGetCount(source)) else { throw WorkspaceFileError.unreadableImage }
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 100_000, height <= 100_000, width <= 100_000_000 / height else { throw WorkspaceFileError.unreadableImage }
        }
        return source
    }
    private func render(_ page: CGPDFPage) throws -> CGImage {
        let bounds = page.getBoxRect(.cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw WorkspaceFileError.unreadablePDF }
        let rotated = abs(page.rotationAngle) % 180 == 90
        let width = rotated ? bounds.height : bounds.width, height = rotated ? bounds.width : bounds.height
        let scale = min(3, 2_600 / max(width, height))
        let rect = CGRect(x: 0, y: 0, width: max(1, ceil(width * scale)), height: max(1, ceil(height * scale)))
        guard let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw WorkspaceFileError.unreadablePDF }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw WorkspaceFileError.unreadablePDF }
        return image
    }
}
