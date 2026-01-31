import Foundation
import SwiftData

// MARK: - Keyword Rule

/// A single keyword rule with weight and matching logic
struct KeywordRule: Codable, Hashable, Sendable {
    /// The phrase to match (e.g., "do zapłaty", "amount due")
    let phrase: String

    /// Weight/score adjustment when this phrase matches
    let weight: Int

    /// Language hint (optional): "pl", "en", nil = any
    let lang: String?

    /// Match type: how to match this phrase
    let matchType: MatchType

    enum MatchType: String, Codable, Sendable {
        case contains   // Phrase appears anywhere in context
        case equals     // Exact match
        case regex      // Regular expression (future)
    }

    init(phrase: String, weight: Int, lang: String? = nil, matchType: MatchType = .contains) {
        self.phrase = phrase
        self.weight = weight
        self.lang = lang
        self.matchType = matchType
    }

    /// Check if this rule matches the given context
    func matches(_ context: String) -> Bool {
        let normalized = context.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        let normalizedPhrase = phrase.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        switch matchType {
        case .contains:
            return normalized.contains(normalizedPhrase)
        case .equals:
            return normalized == normalizedPhrase
        case .regex:
            // Future: regex matching
            return normalized.contains(normalizedPhrase)
        }
    }
}

// MARK: - Weights Configuration

/// Default weight configuration for keyword scoring
struct WeightsConfig: Codable, Hashable, Sendable {
    let payDue: Int           // +100
    let totalPayable: Int     // +40
    let total: Int            // +20
    let discount: Int         // -80
    let vat: Int              // -50
    let net: Int              // -30

    static let `default` = WeightsConfig(
        payDue: 100,
        totalPayable: 40,
        total: 20,
        discount: -80,
        vat: -50,
        net: -30
    )
}

// MARK: - Document Region

/// Preferred region for field extraction (layout hints)
enum DocumentRegion: String, Codable, Sendable {
    case topLeft
    case topRight
    case middle
    case bottomLeft
    case bottomRight
}

// MARK: - Layout Hints

/// Layout preferences for a vendor (where fields typically appear)
struct LayoutHints: Codable, Hashable, Sendable {
    let preferredAmountRegion: DocumentRegion?
    let preferredDueDateRegion: DocumentRegion?
    let regionConfidence: Double  // 0.0-1.0

    init(
        preferredAmountRegion: DocumentRegion? = nil,
        preferredDueDateRegion: DocumentRegion? = nil,
        regionConfidence: Double = 0.0
    ) {
        self.preferredAmountRegion = preferredAmountRegion
        self.preferredDueDateRegion = preferredDueDateRegion
        self.regionConfidence = regionConfidence
    }
}

// MARK: - Vendor Keyword Overrides

/// Vendor-specific keyword overrides that supplement/replace global keywords
struct VendorKeywordOverrides: Codable, Hashable, Sendable {
    let payDue: [KeywordRule]
    let dueDate: [KeywordRule]
    let total: [KeywordRule]
    let negative: [KeywordRule]

    /// Global phrases that should be DISABLED for this vendor
    let disabledGlobalPhrases: [String]

    init(
        payDue: [KeywordRule] = [],
        dueDate: [KeywordRule] = [],
        total: [KeywordRule] = [],
        negative: [KeywordRule] = [],
        disabledGlobalPhrases: [String] = []
    ) {
        self.payDue = payDue
        self.dueDate = dueDate
        self.total = total
        self.negative = negative
        self.disabledGlobalPhrases = disabledGlobalPhrases
    }

    static let empty = VendorKeywordOverrides()
}

// MARK: - Vendor Stats

/// Statistics about vendor profile performance
struct VendorStats: Codable, Hashable, Sendable {
    var totalInvoices: Int
    var successfulExtractions: Int
    var userCorrections: Int
    var lastAccuracyScore: Double  // 0.0-1.0

    var accuracyRate: Double {
        guard totalInvoices > 0 else { return 0.0 }
        return Double(successfulExtractions) / Double(totalInvoices)
    }

    init(
        totalInvoices: Int = 0,
        successfulExtractions: Int = 0,
        userCorrections: Int = 0,
        lastAccuracyScore: Double = 0.0
    ) {
        self.totalInvoices = totalInvoices
        self.successfulExtractions = successfulExtractions
        self.userCorrections = userCorrections
        self.lastAccuracyScore = lastAccuracyScore
    }
}

// MARK: - Vendor Profile Source

/// How was this vendor profile created
enum VendorProfileSource: String, Codable, Sendable {
    case userCreated    // User manually created
    case autoLearned    // System learned from user corrections
    case prebuilt       // Shipped with app (future: common vendors)
}

// MARK: - Keyword Stat State

/// Learning state for a keyword candidate
enum KeywordStatState: String, Codable, Sendable {
    case candidate  // Being tested (hits < 3)
    case promoted   // Promoted to vendor keywords (hits >= 3, misses == 0)
    case blocked    // Blocked due to too many misses (misses >= 2)
}

// MARK: - Field Type

/// Type of field being learned
enum FieldType: String, Codable, Sendable {
    case amount
    case dueDate
    case vendor
    case documentNumber
}
