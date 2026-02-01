import Foundation
import SwiftData

/// Global keyword configuration (versioned, immutable per version)
/// Provides baseline keywords when vendor is unknown
@Model
final class GlobalKeywordConfig {

    // MARK: - Identity

    /// Stable identifier (always "global" for singleton-like behavior)
    @Attribute(.unique) var configId: String

    /// Version number (1, 2, 3...) - increment when updating rules
    var version: Int

    /// When this version was created/updated
    var updatedAt: Date

    // MARK: - Keyword Rules

    /// Keywords indicating "amount to pay" (bilingual)
    @Attribute(.externalStorage)
    var payDueKeywords: [KeywordRule]

    /// Keywords for due date (bilingual)
    @Attribute(.externalStorage)
    var dueDateKeywords: [KeywordRule]

    /// Keywords for total amount (bilingual)
    @Attribute(.externalStorage)
    var totalKeywords: [KeywordRule]

    /// Keywords to penalize (negative indicators)
    @Attribute(.externalStorage)
    var negativeKeywords: [KeywordRule]

    // MARK: - Configuration

    /// Currency hints for detection (e.g., ["pln", "zl", "zł", "eur"])
    var currencyHints: [String]

    /// Default weight configuration
    @Attribute(.externalStorage)
    var weights: WeightsConfig

    // MARK: - Initialization

    init(
        configId: String = "global",
        version: Int,
        payDueKeywords: [KeywordRule] = [],
        dueDateKeywords: [KeywordRule] = [],
        totalKeywords: [KeywordRule] = [],
        negativeKeywords: [KeywordRule] = [],
        currencyHints: [String] = [],
        weights: WeightsConfig = .default
    ) {
        self.configId = configId
        self.version = version
        self.updatedAt = Date()
        self.payDueKeywords = payDueKeywords
        self.dueDateKeywords = dueDateKeywords
        self.totalKeywords = totalKeywords
        self.negativeKeywords = negativeKeywords
        self.currencyHints = currencyHints
        self.weights = weights
    }

    // MARK: - Default Configuration (v1)

    /// Creates the initial global configuration (version 1)
    static func createDefaultV1() -> GlobalKeywordConfig {
        let payDueRules: [KeywordRule] = [
            // Polish - high priority
            KeywordRule(phrase: "do zapłaty", weight: 100, lang: "pl"),
            KeywordRule(phrase: "do zaplaty", weight: 100, lang: "pl"),
            KeywordRule(phrase: "kwota do zapłaty", weight: 100, lang: "pl"),
            KeywordRule(phrase: "należność", weight: 100, lang: "pl"),
            KeywordRule(phrase: "naleznosc", weight: 100, lang: "pl"),
            KeywordRule(phrase: "suma do zapłaty", weight: 100, lang: "pl"),
            KeywordRule(phrase: "płatne", weight: 90, lang: "pl"),
            KeywordRule(phrase: "platne", weight: 90, lang: "pl"),
            // English - high priority
            KeywordRule(phrase: "amount due", weight: 100, lang: "en"),
            KeywordRule(phrase: "amount payable", weight: 100, lang: "en"),
            KeywordRule(phrase: "total payable", weight: 100, lang: "en"),
            KeywordRule(phrase: "to pay", weight: 100, lang: "en"),
            KeywordRule(phrase: "due", weight: 90, lang: "en"),
            KeywordRule(phrase: "payment amount", weight: 90, lang: "en"),
        ]

        let dueDateRules: [KeywordRule] = [
            // Polish
            KeywordRule(phrase: "termin płatności", weight: 100, lang: "pl"),
            KeywordRule(phrase: "termin platnosci", weight: 100, lang: "pl"),
            KeywordRule(phrase: "data płatności", weight: 100, lang: "pl"),
            KeywordRule(phrase: "płatność do", weight: 90, lang: "pl"),
            KeywordRule(phrase: "zapłata do", weight: 90, lang: "pl"),
            KeywordRule(phrase: "płatne do", weight: 90, lang: "pl"),
            KeywordRule(phrase: "do dnia", weight: 80, lang: "pl"),
            // English
            KeywordRule(phrase: "due date", weight: 100, lang: "en"),
            KeywordRule(phrase: "payment due", weight: 100, lang: "en"),
            KeywordRule(phrase: "pay by", weight: 90, lang: "en"),
            KeywordRule(phrase: "payment deadline", weight: 90, lang: "en"),
            KeywordRule(phrase: "payable by", weight: 90, lang: "en"),
        ]

        let totalRules: [KeywordRule] = [
            // Polish
            KeywordRule(phrase: "razem", weight: 20, lang: "pl"),
            KeywordRule(phrase: "suma", weight: 20, lang: "pl"),
            KeywordRule(phrase: "wartość", weight: 20, lang: "pl"),
            KeywordRule(phrase: "wartosc", weight: 20, lang: "pl"),
            KeywordRule(phrase: "brutto", weight: 20, lang: "pl"),
            KeywordRule(phrase: "ogółem", weight: 20, lang: "pl"),
            KeywordRule(phrase: "ogolem", weight: 20, lang: "pl"),
            // English
            KeywordRule(phrase: "total", weight: 20, lang: "en"),
            KeywordRule(phrase: "sum", weight: 20, lang: "en"),
            KeywordRule(phrase: "gross", weight: 20, lang: "en"),
            KeywordRule(phrase: "amount", weight: 15, lang: "en"),
        ]

        let negativeRules: [KeywordRule] = [
            // Polish - discounts
            KeywordRule(phrase: "rabat", weight: -80, lang: "pl"),
            KeywordRule(phrase: "zniżka", weight: -80, lang: "pl"),
            KeywordRule(phrase: "znizka", weight: -80, lang: "pl"),
            KeywordRule(phrase: "odliczenie", weight: -80, lang: "pl"),
            KeywordRule(phrase: "korekta", weight: -70, lang: "pl"),
            KeywordRule(phrase: "zwrot", weight: -70, lang: "pl"),
            // English - discounts
            KeywordRule(phrase: "discount", weight: -80, lang: "en"),
            KeywordRule(phrase: "deduction", weight: -80, lang: "en"),
            KeywordRule(phrase: "refund", weight: -70, lang: "en"),
            KeywordRule(phrase: "correction", weight: -70, lang: "en"),
            // VAT/Tax (language-neutral)
            KeywordRule(phrase: "vat", weight: -50),
            KeywordRule(phrase: "podatek", weight: -50, lang: "pl"),
            KeywordRule(phrase: "tax", weight: -50, lang: "en"),
            KeywordRule(phrase: "netto", weight: -30, lang: "pl"),
            KeywordRule(phrase: "net", weight: -30, lang: "en"),
        ]

        let currencyHints = ["pln", "zl", "zł", "złotych", "eur", "€", "euro", "usd", "$", "dolar"]

        return GlobalKeywordConfig(
            configId: "global",
            version: 1,
            payDueKeywords: payDueRules,
            dueDateKeywords: dueDateRules,
            totalKeywords: totalRules,
            negativeKeywords: negativeRules,
            currencyHints: currencyHints,
            weights: .default
        )
    }

    /// Get all keywords for a specific field type
    func getKeywords(for fieldType: FieldType) -> [KeywordRule] {
        switch fieldType {
        case .amount:
            return payDueKeywords + totalKeywords
        case .dueDate:
            return dueDateKeywords
        case .vendor, .documentNumber, .nip, .bankAccount:
            return []
        }
    }

    /// Calculate score for context using this config's rules
    func calculateScore(for fieldType: FieldType, context: String) -> (score: Int, matchedRules: [KeywordRule]) {
        let keywords = getKeywords(for: fieldType) + negativeKeywords
        var totalScore = 0
        var matched: [KeywordRule] = []

        for rule in keywords {
            if rule.matches(context) {
                totalScore += rule.weight
                matched.append(rule)
            }
        }

        return (totalScore, matched)
    }

    // MARK: - Backward Compatibility Helpers

    /// Get phrases as strings (for backward compatibility with old VendorProfile API)
    func getPayDuePhrases() -> [String] {
        return payDueKeywords.map { $0.phrase }
    }

    func getDueDatePhrases() -> [String] {
        return dueDateKeywords.map { $0.phrase }
    }

    func getTotalPhrases() -> [String] {
        return totalKeywords.map { $0.phrase }
    }

    func getNegativePhrases() -> [String] {
        return negativeKeywords.map { $0.phrase }
    }

    /// Get weight values as dictionary (for backward compatibility)
    func getWeightValues() -> [String: Int] {
        return [
            "payDue": weights.payDue,
            "totalPayable": weights.totalPayable,
            "total": weights.total,
            "discount": weights.discount,
            "vat": weights.vat,
            "net": weights.net
        ]
    }
}
