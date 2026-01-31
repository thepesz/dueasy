import Foundation
import os.log

/// Service for learning and storing keywords from user corrections.
/// Helps improve parsing accuracy by learning from successful detections
/// and manual corrections.
///
/// Storage strategy: UserDefaults for learned keywords (simple key-value pairs)
/// Structure: Field type -> Keyword -> Confidence score
final class KeywordLearningService: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "KeywordLearning")
    private let defaults: UserDefaults

    // MARK: - Keys

    private enum Keys {
        static let learnedAmountKeywords = "learnedAmountKeywords"
        static let learnedVendorKeywords = "learnedVendorKeywords"
        static let learnedDueDateKeywords = "learnedDueDateKeywords"
        static let learnedInvoiceNumberKeywords = "learnedInvoiceNumberKeywords"
        static let learningVersion = "keywordLearningVersion"
    }

    // MARK: - Data Structures

    /// Learned keyword with confidence score
    struct LearnedKeyword: Codable, Sendable {
        let keyword: String
        var confidence: Int // 0-100
        var timesUsed: Int
        var lastUsed: Date

        init(keyword: String, confidence: Int = 50) {
            self.keyword = keyword.lowercased()
            self.confidence = confidence
            self.timesUsed = 1
            self.lastUsed = Date()
        }

        mutating func recordSuccess() {
            timesUsed += 1
            confidence = min(100, confidence + 5) // Increase confidence on success
            lastUsed = Date()
        }

        mutating func recordFailure() {
            confidence = max(0, confidence - 10) // Decrease confidence on failure
        }
    }

    /// Field type for learned keywords
    enum FieldType: String {
        case amount
        case vendor
        case dueDate
        case invoiceNumber
    }

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateIfNeeded()
    }

    private func migrateIfNeeded() {
        let currentVersion = 1
        let storedVersion = defaults.integer(forKey: Keys.learningVersion)

        if storedVersion < currentVersion {
            logger.info("Migrating keyword learning data from version \(storedVersion) to \(currentVersion)")
            // Add migration logic here if needed in future versions
            defaults.set(currentVersion, forKey: Keys.learningVersion)
        }
    }

    // MARK: - Public API

    /// Get all learned keywords for a specific field type
    func getLearnedKeywords(for fieldType: FieldType) -> [LearnedKeyword] {
        let key = storageKey(for: fieldType)
        guard let data = defaults.data(forKey: key),
              let keywords = try? JSONDecoder().decode([LearnedKeyword].self, from: data) else {
            return []
        }

        // Filter out low-confidence keywords (below 20)
        let filtered = keywords.filter { $0.confidence >= 20 }
        logger.debug("Retrieved \(filtered.count) learned keywords for \(fieldType.rawValue)")
        return filtered
    }

    /// Learn a new keyword from successful detection
    /// - Parameters:
    ///   - keyword: The keyword that appeared near the detected value
    ///   - fieldType: Type of field this keyword is associated with
    ///   - initialConfidence: Initial confidence score (default: 50)
    func learnKeyword(_ keyword: String, for fieldType: FieldType, initialConfidence: Int = 50) {
        let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        // Skip if keyword is too generic
        let genericKeywords = ["faktura", "invoice", "data", "date", "nr", "no"]
        if genericKeywords.contains(normalized) {
            logger.debug("Skipping generic keyword: '\(normalized)'")
            return
        }

        var keywords = getLearnedKeywords(for: fieldType)

        // Check if keyword already exists
        if let index = keywords.firstIndex(where: { $0.keyword == normalized }) {
            // Update existing keyword
            keywords[index].recordSuccess()
            logger.info("Updated existing keyword '\(normalized)' for \(fieldType.rawValue), new confidence: \(keywords[index].confidence)")
        } else {
            // Add new keyword
            let newKeyword = LearnedKeyword(keyword: normalized, confidence: initialConfidence)
            keywords.append(newKeyword)
            logger.info("Learned new keyword '\(normalized)' for \(fieldType.rawValue) with confidence: \(initialConfidence)")
        }

        // Save
        saveKeywords(keywords, for: fieldType)
    }

    /// Learn from user correction: extract keywords from context where correct value was found
    /// - Parameters:
    ///   - correctedValue: The correct value that user entered
    ///   - ocrText: Full OCR text to search for context
    ///   - fieldType: Type of field being corrected
    func learnFromCorrection(correctedValue: String, ocrText: String, fieldType: FieldType) {
        logger.info("Learning from user correction for \(fieldType.rawValue): '\(correctedValue)'")

        let lowercasedText = ocrText.lowercased()
        let lowercasedValue = correctedValue.lowercased()

        // For amounts, use normalized search to handle OCR variations
        let range: Range<String.Index>?
        if fieldType == .amount {
            range = findAmountInText(amount: lowercasedValue, text: lowercasedText)
        } else {
            range = lowercasedText.range(of: lowercasedValue)
        }

        guard let foundRange = range else {
            logger.warning("Could not find corrected value '\(correctedValue)' in OCR text")
            return
        }

        // Extract context around the value (50 chars before)
        let contextStartIndex = lowercasedText.index(foundRange.lowerBound, offsetBy: -50, limitedBy: lowercasedText.startIndex) ?? lowercasedText.startIndex
        let contextEndIndex = foundRange.lowerBound
        let context = String(lowercasedText[contextStartIndex..<contextEndIndex])

        logger.debug("Context before corrected value: '\(context)'")

        // Extract potential keywords from context
        let potentialKeywords = extractKeywordsFromContext(context)

        // Learn keywords with medium confidence (they appeared near correct value)
        for keyword in potentialKeywords {
            learnKeyword(keyword, for: fieldType, initialConfidence: 60)
        }
    }

    /// Record that a keyword was used successfully in detection
    func recordSuccess(keyword: String, for fieldType: FieldType) {
        let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var keywords = getLearnedKeywords(for: fieldType)

        if let index = keywords.firstIndex(where: { $0.keyword == normalized }) {
            keywords[index].recordSuccess()
            saveKeywords(keywords, for: fieldType)
            logger.debug("Recorded success for keyword '\(normalized)' in \(fieldType.rawValue)")
        }
    }

    /// Record that a keyword led to incorrect detection
    func recordFailure(keyword: String, for fieldType: FieldType) {
        let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var keywords = getLearnedKeywords(for: fieldType)

        if let index = keywords.firstIndex(where: { $0.keyword == normalized }) {
            keywords[index].recordFailure()

            // Remove keyword if confidence drops too low
            if keywords[index].confidence < 10 {
                keywords.remove(at: index)
                logger.info("Removed low-confidence keyword '\(normalized)' from \(fieldType.rawValue)")
            }

            saveKeywords(keywords, for: fieldType)
            logger.debug("Recorded failure for keyword '\(normalized)' in \(fieldType.rawValue)")
        }
    }

    /// Clear all learned keywords (for testing or reset)
    func clearAllLearned() {
        for fieldType in [FieldType.amount, .vendor, .dueDate, .invoiceNumber] {
            defaults.removeObject(forKey: storageKey(for: fieldType))
        }
        logger.info("Cleared all learned keywords")
    }

    /// Get statistics about learned keywords
    func getStatistics() -> [FieldType: Int] {
        var stats: [FieldType: Int] = [:]
        for fieldType in [FieldType.amount, .vendor, .dueDate, .invoiceNumber] {
            stats[fieldType] = getLearnedKeywords(for: fieldType).count
        }
        return stats
    }

    // MARK: - Private Methods

    private func storageKey(for fieldType: FieldType) -> String {
        switch fieldType {
        case .amount:
            return Keys.learnedAmountKeywords
        case .vendor:
            return Keys.learnedVendorKeywords
        case .dueDate:
            return Keys.learnedDueDateKeywords
        case .invoiceNumber:
            return Keys.learnedInvoiceNumberKeywords
        }
    }

    private func saveKeywords(_ keywords: [LearnedKeyword], for fieldType: FieldType) {
        let key = storageKey(for: fieldType)
        if let data = try? JSONEncoder().encode(keywords) {
            defaults.set(data, forKey: key)
            logger.debug("Saved \(keywords.count) keywords for \(fieldType.rawValue)")
        } else {
            logger.error("Failed to encode keywords for \(fieldType.rawValue)")
        }
    }

    /// Extract potential keywords from context text
    /// Returns meaningful words/phrases that could be keywords
    private func extractKeywordsFromContext(_ context: String) -> [String] {
        // Split by whitespace and punctuation
        let words = context.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count >= 3 } // At least 3 characters

        // Look for 1-3 word phrases near the end of context (most likely to be labels)
        var keywords: [String] = []

        // Last 1-3 words
        let lastWords = words.suffix(3)
        if lastWords.count >= 1 {
            keywords.append(lastWords.joined(separator: " "))
        }
        if lastWords.count >= 2 {
            keywords.append(lastWords.suffix(2).joined(separator: " "))
        }

        // Individual words that might be keywords
        for word in lastWords {
            if word.count >= 4 { // Longer words more likely to be meaningful
                keywords.append(word)
            }
        }

        return keywords
    }

    /// Find amount in text with normalization to handle OCR variations
    /// Handles: spaces (including non-breaking), comma vs period decimal separators
    /// - Parameters:
    ///   - amount: The amount to search for (e.g., "2.00", "1234.56")
    ///   - text: The OCR text to search in
    /// - Returns: Range of the found amount, or nil if not found
    private func findAmountInText(amount: String, text: String) -> Range<String.Index>? {
        // Normalize the amount: remove all whitespace, get digits and decimal separator
        let normalizedAmount = normalizeAmount(amount)

        // Try to find the amount in various OCR formats
        let searchVariants = generateAmountVariants(normalizedAmount)

        for variant in searchVariants {
            if let range = text.range(of: variant) {
                logger.debug("Found amount '\(amount)' as '\(variant)' in OCR text")
                return range
            }
        }

        logger.debug("Could not find amount '\(amount)' in any normalized form")
        return nil
    }

    /// Normalize amount by removing all whitespace and standardizing decimal separator
    /// - Parameter amount: The amount string (e.g., "2.00", "1 234,56")
    /// - Returns: Normalized amount (e.g., "2.00", "1234.56")
    private func normalizeAmount(_ amount: String) -> String {
        // Remove all whitespace (including non-breaking spaces U+00A0)
        var normalized = amount.replacingOccurrences(of: " ", with: "")
        normalized = normalized.replacingOccurrences(of: "\u{00A0}", with: "") // non-breaking space
        normalized = normalized.replacingOccurrences(of: "\u{202F}", with: "") // narrow no-break space

        // Standardize to period as decimal separator
        // If there's a comma followed by 2 digits at the end, it's likely a decimal separator
        if let commaRange = normalized.range(of: ",", options: .backwards),
           commaRange.upperBound != normalized.endIndex {
            let afterComma = normalized[commaRange.upperBound...]
            if afterComma.count <= 2 && afterComma.allSatisfy({ $0.isNumber }) {
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            }
        }

        return normalized
    }

    /// Generate search variants for an amount to handle OCR variations
    /// - Parameter normalizedAmount: Normalized amount (e.g., "1234.56")
    /// - Returns: Array of search variants (with spaces, with comma, etc.)
    private func generateAmountVariants(_ normalizedAmount: String) -> [String] {
        var variants: [String] = []

        // Original normalized version
        variants.append(normalizedAmount)

        // Version with comma instead of period
        let withComma = normalizedAmount.replacingOccurrences(of: ".", with: ",")
        variants.append(withComma)

        // Versions with spaces (for thousands separators)
        // e.g., "1234.56" -> "1 234.56", "1 234,56"
        if let periodIndex = normalizedAmount.firstIndex(of: ".") {
            let integerPart = String(normalizedAmount[..<periodIndex])
            let decimalPart = String(normalizedAmount[periodIndex...])

            if integerPart.count > 3 {
                // Add space as thousands separator
                let spacedInteger = addThousandsSeparator(integerPart, separator: " ")
                variants.append(spacedInteger + decimalPart)
                variants.append(spacedInteger + decimalPart.replacingOccurrences(of: ".", with: ","))

                // Also try with non-breaking space
                let nbspInteger = addThousandsSeparator(integerPart, separator: "\u{00A0}")
                variants.append(nbspInteger + decimalPart)
                variants.append(nbspInteger + decimalPart.replacingOccurrences(of: ".", with: ","))
            }
        }

        // Version with space before/after decimal separator (OCR errors)
        // e.g., "2. 00", "2 .00", "2 . 00"
        if let periodIndex = normalizedAmount.firstIndex(of: ".") {
            let before = String(normalizedAmount[..<periodIndex])
            let after = String(normalizedAmount[normalizedAmount.index(after: periodIndex)...])
            variants.append("\(before). \(after)")
            variants.append("\(before) .\(after)")
            variants.append("\(before) . \(after)")
            // Same with comma
            variants.append("\(before), \(after)")
            variants.append("\(before) ,\(after)")
            variants.append("\(before) , \(after)")
        }

        logger.debug("Generated \(variants.count) search variants for amount '\(normalizedAmount)'")
        return variants
    }

    /// Add thousands separator to integer string
    /// - Parameters:
    ///   - integer: Integer part as string (e.g., "1234567")
    ///   - separator: Separator to use (e.g., " " or ",")
    /// - Returns: String with separator (e.g., "1 234 567")
    private func addThousandsSeparator(_ integer: String, separator: String) -> String {
        var result = ""
        var count = 0
        for char in integer.reversed() {
            if count > 0 && count % 3 == 0 {
                result = separator + result
            }
            result = String(char) + result
            count += 1
        }
        return result
    }
}
