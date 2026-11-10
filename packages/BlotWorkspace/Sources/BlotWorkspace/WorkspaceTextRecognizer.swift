import CoreGraphics
import ImageIO
import Foundation
import Vision

public protocol WorkspaceTextRecognizing: Sendable {
    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> String
}

/// Uses the OS's installed recognition models. No image is uploaded to an OCR service.
public struct WorkspaceVisionTextRecognizer: WorkspaceTextRecognizing {
    public init() {}
    public func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
        try _Concurrency.Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["ru-RU", "en-US"].filter(supported.contains)
        do { try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request]) }
        catch { try _Concurrency.Task.checkCancellation(); throw WorkspaceFileError.recognitionFailed }
        try _Concurrency.Task.checkCancellation()
        // Vision returns text observations in reading order, including mixed-language lines.
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
