import CoreFoundation
import Foundation
import ImageIO
import UIKit

nonisolated enum PhoneAvatarImage {
    enum Failure: Error { case invalidImage }

    static func prepare(_ data: Data) throws -> Data {
        guard let image = thumbnail(data, pixels: 512),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw Failure.invalidImage }
        return jpeg
    }

    static func thumbnail(_ data: Data, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
