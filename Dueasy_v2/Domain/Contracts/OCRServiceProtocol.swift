import Foundation
import UIKit

/// Protocol for Optical Character Recognition services.
/// Iteration 1: Apple Vision on-device OCR.
/// Iteration 2: Can route to backend for enhanced AI extraction.
protocol OCRServiceProtocol: Sendable {

    /// Recognizes text from images.
    /// - Parameter images: Array of images to process
    /// - Returns: Combined recognized text from all images
    /// - Throws: `AppError.ocrFailed`, `AppError.ocrNoTextFound`
    func recognizeText(from images: [UIImage]) async throws -> OCRResult

    /// Recognizes text from a single image.
    /// - Parameter image: Image to process
    /// - Returns: Recognized text
    /// - Throws: `AppError.ocrFailed`, `AppError.ocrNoTextFound`
    func recognizeText(from image: UIImage) async throws -> OCRResult

    /// Supported languages for OCR.
    var supportedLanguages: [String] { get }

    /// Currently configured recognition languages.
    var recognitionLanguages: [String] { get }

    /// Updates the recognition languages.
    /// - Parameter languages: Array of language codes (e.g., ["en", "pl"])
    func setRecognitionLanguages(_ languages: [String])
}

/// Result of OCR operation including confidence metadata.
struct OCRResult: Sendable, Equatable {

    /// Combined recognized text
    let text: String

    /// Overall confidence score (0.0 to 1.0)
    let confidence: Double

    /// Per-line confidence scores (optional)
    let lineConfidences: [Double]?

    /// Structured line data with bounding boxes (for learning)
    /// Only populated when capturing for learning purposes
    let lineData: [OCRLineData]?

    /// Whether the result has low confidence
    var isLowConfidence: Bool {
        confidence < 0.5
    }

    /// Whether any text was recognized
    var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(text: String, confidence: Double, lineConfidences: [Double]? = nil, lineData: [OCRLineData]? = nil) {
        self.text = text
        self.confidence = confidence
        self.lineConfidences = lineConfidences
        self.lineData = lineData
    }

    static let empty = OCRResult(text: "", confidence: 0.0, lineConfidences: nil, lineData: nil)
}
