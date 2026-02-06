import Foundation

// MARK: - String Matching Service

/// Implementation of StringMatchingServiceProtocol for vendor spoofing detection.
/// Provides Levenshtein distance, homoglyph detection, and similarity scoring.
///
/// Thread-safe and Sendable - can be used from any context.
final class StringMatchingService: StringMatchingServiceProtocol, Sendable {

    // MARK: - Homoglyph Map

    /// Map of Latin characters to their Cyrillic/Greek lookalikes.
    /// Used for detecting homoglyph-based spoofing attacks.
    ///
    /// Format: Latin character -> [Lookalike characters]
    /// Common attack vectors include Cyrillic characters that look identical to Latin.
    private static let homoglyphMap: [Character: [Character]] = [
        // Latin to Cyrillic lookalikes
        "a": ["\u{0430}"], // Cyrillic Small Letter A
        "A": ["\u{0410}"], // Cyrillic Capital Letter A
        "c": ["\u{0441}"], // Cyrillic Small Letter ES
        "C": ["\u{0421}"], // Cyrillic Capital Letter ES
        "e": ["\u{0435}"], // Cyrillic Small Letter IE
        "E": ["\u{0415}"], // Cyrillic Capital Letter IE
        "i": ["\u{0456}"], // Cyrillic Small Letter Byelorussian-Ukrainian I
        "I": ["\u{0406}"], // Cyrillic Capital Letter Byelorussian-Ukrainian I
        "o": ["\u{043E}"], // Cyrillic Small Letter O
        "O": ["\u{041E}"], // Cyrillic Capital Letter O
        "p": ["\u{0440}"], // Cyrillic Small Letter ER
        "P": ["\u{0420}"], // Cyrillic Capital Letter ER
        "x": ["\u{0445}"], // Cyrillic Small Letter HA
        "X": ["\u{0425}"], // Cyrillic Capital Letter HA
        "y": ["\u{0443}"], // Cyrillic Small Letter U
        "Y": ["\u{0423}"], // Cyrillic Capital Letter U
        "s": ["\u{0455}"], // Cyrillic Small Letter DZE
        "S": ["\u{0405}"], // Cyrillic Capital Letter DZE

        // Latin to Greek lookalikes
        "B": ["\u{0392}"], // Greek Capital Letter Beta
        "H": ["\u{0397}"], // Greek Capital Letter Eta
        "K": ["\u{039A}"], // Greek Capital Letter Kappa
        "M": ["\u{039C}"], // Greek Capital Letter Mu
        "N": ["\u{039D}"], // Greek Capital Letter Nu
        "T": ["\u{03A4}"], // Greek Capital Letter Tau
        "Z": ["\u{0396}"], // Greek Capital Letter Zeta
        "v": ["\u{03BD}"], // Greek Small Letter Nu
        "n": ["\u{03B7}"], // Greek Small Letter Eta (eta looks like n)

        // Additional confusables
        "l": ["1", "\u{0406}"], // Digit 1, Cyrillic I
        "0": ["\u{041E}", "\u{03BF}"], // Cyrillic O, Greek Omicron
        "1": ["l", "\u{0406}"], // Latin L, Cyrillic I
    ]

    /// Reverse map: Homoglyph -> Latin equivalent
    private static let reverseHomoglyphMap: [Character: Character] = {
        var reverse: [Character: Character] = [:]
        for (latin, homoglyphs) in homoglyphMap {
            for homoglyph in homoglyphs {
                reverse[homoglyph] = latin
            }
        }
        return reverse
    }()

    // MARK: - Initialization

    init() {}

    // MARK: - Levenshtein Distance

    func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        // Normalize for comparison
        let str1 = normalizeForComparison(s1)
        let str2 = normalizeForComparison(s2)

        // Early exits
        if str1 == str2 { return 0 }
        if str1.isEmpty { return str2.count }
        if str2.isEmpty { return str1.count }

        // Convert to arrays for O(1) access
        let arr1 = Array(str1)
        let arr2 = Array(str2)
        let m = arr1.count
        let n = arr2.count

        // Create DP matrix
        // Optimization: only keep two rows instead of full matrix
        var previousRow = Array(0...n)
        var currentRow = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            currentRow[0] = i

            for j in 1...n {
                let cost = arr1[i - 1] == arr2[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,      // Deletion
                    currentRow[j - 1] + 1,   // Insertion
                    previousRow[j - 1] + cost // Substitution
                )
            }

            // Swap rows
            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }

    // MARK: - Homoglyph Detection

    func detectHomoglyphs(in suspicious: String, comparing original: String) -> HomoglyphDetectionResult {
        // Normalize strings for character-by-character comparison
        let normalizedOriginal = normalizeForComparison(original)
        let suspiciousChars = Array(suspicious)

        var positions: [Int] = []
        var homoglyphChars: [Character] = []

        for (index, char) in suspiciousChars.enumerated() {
            // Check if this character is a known homoglyph
            if let latinEquivalent = Self.reverseHomoglyphMap[char] {
                // Verify the original would have this Latin character
                // (we're looking for intentional substitution)
                let normalizedChar = String(char).folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                )
                if normalizedOriginal.lowercased().contains(String(latinEquivalent).lowercased()) ||
                   normalizedOriginal.lowercased().contains(normalizedChar.lowercased()) {
                    positions.append(index)
                    homoglyphChars.append(char)
                }
            }
        }

        // Calculate spoofing confidence
        let confidence: Double
        if positions.isEmpty {
            confidence = 0.0
        } else {
            // More homoglyphs = higher confidence
            // But also consider the ratio of homoglyphs to total characters
            let ratio = Double(positions.count) / Double(max(suspiciousChars.count, 1))

            // Confidence increases with both count and ratio
            // 1 homoglyph in a long string is less suspicious than 3 in a short string
            confidence = min(1.0, (Double(positions.count) * 0.2) + (ratio * 0.5))
        }

        return HomoglyphDetectionResult(
            positions: positions,
            homoglyphCharacters: homoglyphChars,
            spoofingConfidence: confidence
        )
    }

    // MARK: - Similarity Score

    func similarityScore(_ s1: String, _ s2: String) -> Double {
        let str1 = normalizeForComparison(s1)
        let str2 = normalizeForComparison(s2)

        // Exact match
        if str1 == str2 {
            return 1.0
        }

        // Empty strings
        if str1.isEmpty || str2.isEmpty {
            return 0.0
        }

        // Calculate Levenshtein distance
        let distance = levenshteinDistance(str1, str2)

        // Convert to similarity score
        // Similarity = 1 - (distance / maxLength)
        let maxLength = max(str1.count, str2.count)
        let similarity = 1.0 - (Double(distance) / Double(maxLength))

        return max(0.0, similarity)
    }

    // MARK: - Normalization

    func normalizeForComparison(_ string: String) -> String {
        // Apply transformations in order:
        // 1. NFD normalization (decompose characters)
        // 2. Remove diacritics
        // 3. Lowercase
        // 4. Trim whitespace
        // 5. Collapse multiple spaces

        var result = string

        // NFD normalization and diacritic removal
        result = result.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: .current
        )

        // Lowercase
        result = result.lowercased()

        // Trim whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse multiple spaces to single space
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Remove common business suffixes that don't affect identity
        // This helps match "Vendor ABC" with "Vendor ABC Sp. z o.o."
        let businessSuffixes = [
            " sp. z o.o.",
            " sp.z o.o.",
            " sp. z.o.o.",
            " s.a.",
            " sp.j.",
            " sp.k.",
            " gmbh",
            " ltd",
            " inc",
            " llc",
            " corp",
            " ag",
        ]

        for suffix in businessSuffixes {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Suspicious Similarity Check

    func areSuspiciouslySimilar(_ s1: String, _ s2: String, threshold: Double = 0.85) -> Bool {
        // First check: exact match after normalization
        let normalized1 = normalizeForComparison(s1)
        let normalized2 = normalizeForComparison(s2)

        if normalized1 == normalized2 {
            return false // Exact match = same vendor, not suspicious
        }

        // Second check: similarity score
        let similarity = similarityScore(s1, s2)
        if similarity >= threshold {
            // High similarity but not identical = suspicious
            return true
        }

        // Third check: homoglyphs (even with lower similarity)
        let homoglyphResult = detectHomoglyphs(in: s2, comparing: s1)
        if homoglyphResult.hasHomoglyphs && homoglyphResult.spoofingConfidence > 0.3 {
            // Has homoglyphs with reasonable confidence = suspicious
            return true
        }

        // Fourth check: Levenshtein distance for short strings
        // For short names (< 10 chars), even 1-2 edits can be suspicious
        if normalized1.count < 10 || normalized2.count < 10 {
            let distance = levenshteinDistance(s1, s2)
            if distance <= 2 && distance > 0 {
                return true
            }
        }

        return false
    }
}

// MARK: - Convenience Extensions

extension StringMatchingService {

    /// Checks if a name might be a variant of another name.
    /// More lenient than areSuspiciouslySimilar - for grouping related vendors.
    /// - Parameters:
    ///   - name1: First name
    ///   - name2: Second name
    /// - Returns: True if names are likely variants
    func areNameVariants(_ name1: String, _ name2: String) -> Bool {
        let normalized1 = normalizeForComparison(name1)
        let normalized2 = normalizeForComparison(name2)

        // Exact match after normalization
        if normalized1 == normalized2 {
            return true
        }

        // One contains the other
        if normalized1.contains(normalized2) || normalized2.contains(normalized1) {
            return true
        }

        // Very high similarity
        let similarity = similarityScore(name1, name2)
        return similarity >= 0.9
    }
}
