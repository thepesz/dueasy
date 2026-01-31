import Foundation

/// Amount candidate detected during parsing, with context for learning
struct AmountCandidate: Codable, Sendable {
    /// The detected amount value
    let value: Decimal

    /// Currency hint from nearby text
    let currencyHint: String?

    /// The line of text where this amount was found
    let lineText: String

    /// Bounding box of the line containing this amount
    let lineBBox: BoundingBox

    /// Keywords found in nearby lines (1-2 lines before/after)
    let nearbyKeywords: [String]

    /// Pattern that matched this amount (for debugging/learning)
    let matchedPattern: String

    /// Confidence score for this candidate (0.0-1.0)
    let confidence: Double

    /// Context text (surrounding lines for learning)
    let context: String
}

/// Date candidate detected during parsing, with context for learning
struct DateCandidate: Codable, Sendable {
    /// The detected date value
    let date: Date

    /// The line of text where this date was found
    let lineText: String

    /// Bounding box of the line containing this date
    let lineBBox: BoundingBox

    /// Keywords found in nearby lines (1-2 lines before/after)
    let nearbyKeywords: [String]

    /// Pattern that matched this date (for debugging/learning)
    let matchedPattern: String

    /// Score assigned to this date (higher = more likely to be due date)
    let score: Int

    /// Reason for the score (for debugging/learning)
    let scoreReason: String

    /// Context text (surrounding lines for learning)
    let context: String
}

/// Vendor candidate detected during parsing
struct VendorCandidate: Codable, Sendable {
    /// The detected vendor name
    let name: String

    /// The line of text where this vendor was found
    let lineText: String

    /// Bounding box of the line containing this vendor
    let lineBBox: BoundingBox

    /// Pattern that matched this vendor (for debugging/learning)
    let matchedPattern: String

    /// Confidence score for this candidate (0.0-1.0)
    let confidence: Double
}
