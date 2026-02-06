import Foundation

// MARK: - Homoglyph Detection Result

/// Result of homoglyph detection between two strings.
struct HomoglyphDetectionResult: Sendable, Equatable {

    /// Positions in the original string where homoglyphs were detected
    let positions: [Int]

    /// Characters that are potential homoglyphs
    let homoglyphCharacters: [Character]

    /// Whether any homoglyphs were detected
    var hasHomoglyphs: Bool {
        !positions.isEmpty
    }

    /// Number of homoglyphs found
    var count: Int {
        positions.count
    }

    /// Confidence score that this is intentional spoofing (0.0-1.0)
    /// Higher score = more likely intentional
    let spoofingConfidence: Double

    static let none = HomoglyphDetectionResult(
        positions: [],
        homoglyphCharacters: [],
        spoofingConfidence: 0.0
    )
}

// MARK: - String Matching Service Protocol

/// Protocol for string matching and similarity services.
/// Used for vendor spoofing detection and fuzzy matching.
///
/// Provides:
/// - Levenshtein distance calculation for edit distance
/// - Homoglyph detection for lookalike character attacks
/// - Similarity scoring for fuzzy string matching
protocol StringMatchingServiceProtocol: Sendable {

    /// Calculates the Levenshtein (edit) distance between two strings.
    /// The distance is the minimum number of single-character edits
    /// (insertions, deletions, substitutions) needed to transform one string into another.
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: Edit distance (0 = identical, higher = more different)
    func levenshteinDistance(_ s1: String, _ s2: String) -> Int

    /// Detects homoglyphs (lookalike characters) between two strings.
    /// Homoglyphs are characters that look similar but have different Unicode code points.
    /// Example: Cyrillic 'a' (U+0430) vs Latin 'a' (U+0061)
    /// - Parameters:
    ///   - original: The original/trusted string
    ///   - suspicious: The potentially spoofed string
    /// - Returns: Detection result with positions and confidence
    func detectHomoglyphs(in suspicious: String, comparing original: String) -> HomoglyphDetectionResult

    /// Calculates a similarity score between two strings.
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: Similarity score from 0.0 (completely different) to 1.0 (identical)
    func similarityScore(_ s1: String, _ s2: String) -> Double

    /// Normalizes a string for comparison.
    /// Applies: lowercase, NFD normalization, whitespace trimming, diacritic removal.
    /// - Parameter string: String to normalize
    /// - Returns: Normalized string
    func normalizeForComparison(_ string: String) -> String

    /// Checks if two strings are similar enough to be potential spoofs.
    /// Uses a combination of Levenshtein distance and homoglyph detection.
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    ///   - threshold: Similarity threshold (0.0-1.0, default 0.85)
    /// - Returns: True if strings are suspiciously similar
    func areSuspiciouslySimilar(_ s1: String, _ s2: String, threshold: Double) -> Bool
}

// MARK: - Default Implementations

extension StringMatchingServiceProtocol {

    func areSuspiciouslySimilar(_ s1: String, _ s2: String, threshold: Double = 0.85) -> Bool {
        // First check: exact match after normalization
        let normalized1 = normalizeForComparison(s1)
        let normalized2 = normalizeForComparison(s2)

        if normalized1 == normalized2 {
            return false // Exact match, not suspicious
        }

        // Second check: similarity score
        let similarity = similarityScore(s1, s2)
        if similarity >= threshold {
            return true
        }

        // Third check: homoglyphs
        let homoglyphResult = detectHomoglyphs(in: s2, comparing: s1)
        if homoglyphResult.hasHomoglyphs && homoglyphResult.spoofingConfidence > 0.5 {
            return true
        }

        return false
    }
}
