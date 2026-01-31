import Foundation

/// Structured OCR data for a single recognized line of text.
/// Stored without full invoice content for privacy.
struct OCRLineData: Codable, Sendable, Equatable {
    /// The recognized text content for this line
    let text: String

    /// Page index for multi-page documents (0-based)
    let pageIndex: Int

    /// Bounding box in normalized coordinates (0.0-1.0)
    let bbox: BoundingBox

    /// OCR confidence score (0.0-1.0)
    let confidence: Double

    /// Tokenized words (lowercased, normalized for matching)
    let tokens: [String]

    init(text: String, pageIndex: Int, bbox: BoundingBox, confidence: Double) {
        self.text = text
        self.pageIndex = pageIndex
        self.bbox = bbox
        self.confidence = confidence
        self.tokens = Self.tokenize(text)
    }

    /// Tokenize text into normalized words for keyword matching
    private static func tokenize(_ text: String) -> [String] {
        return text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current) // Remove Polish diacritics
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    // Equatable conformance
    static func == (lhs: OCRLineData, rhs: OCRLineData) -> Bool {
        return lhs.text == rhs.text &&
               lhs.pageIndex == rhs.pageIndex &&
               lhs.bbox == rhs.bbox &&
               lhs.confidence == rhs.confidence &&
               lhs.tokens == rhs.tokens
    }
}
