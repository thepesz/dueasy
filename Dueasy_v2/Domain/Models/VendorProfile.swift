import Foundation
import SwiftData

/// Vendor-specific profile for intelligent invoice parsing
/// Learns keywords and layout patterns from user corrections
@Model
final class VendorProfile {

    // MARK: - Identity

    @Attribute(.unique) var vendorId: UUID
    var displayName: String
    var normalizedName: String  // Lowercase, no diacritics for matching

    // Tax identifiers for matching
    var nip: String?            // Polish Tax ID (10 digits)
    var regon: String?          // Polish Business Registry (9 or 14 digits)

    // MARK: - Learned Keywords (Bilingual)

    /// Keywords that indicate "amount to pay" (e.g., "do zapłaty", "amount due")
    var payDueKeywords: [String]

    /// Keywords for due date (e.g., "termin płatności", "payment date")
    var dueDateKeywords: [String]

    /// Keywords for total amount (e.g., "suma", "razem", "total")
    var totalKeywords: [String]

    /// Keywords to avoid/penalize (e.g., "rabat", "discount", "VAT")
    var negativeKeywords: [String]

    // MARK: - Layout Hints (Optional)

    /// Preferred region for amount (e.g., "bottomRight", "topRight", "middle")
    var preferredRegionForAmount: String?

    /// Preferred region for due date (e.g., "bottomLeft", "middle")
    var preferredRegionForDueDate: String?

    // MARK: - Weight Overrides (Optional)

    /// Custom score adjustments for this vendor
    /// Format: ["do zapłaty": 130, "discount": -100]
    /// These override global weights
    @Attribute(.externalStorage)
    var weightsOverrides: [String: Int]

    // MARK: - Keyword Statistics (for learning)

    /// Track keyword effectiveness: phrase -> (hits, misses)
    /// Promotion rule: hits >= 3 && misses == 0 → promote to permanent keyword
    @Attribute(.externalStorage)
    var keywordStats: [String: KeywordStat]

    // MARK: - Metadata

    var invoiceCount: Int       // Number of invoices from this vendor
    var lastUpdated: Date
    var createdAt: Date

    // MARK: - Initialization

    init(
        vendorId: UUID = UUID(),
        displayName: String,
        nip: String? = nil,
        regon: String? = nil,
        payDueKeywords: [String] = [],
        dueDateKeywords: [String] = [],
        totalKeywords: [String] = [],
        negativeKeywords: [String] = [],
        preferredRegionForAmount: String? = nil,
        preferredRegionForDueDate: String? = nil,
        weightsOverrides: [String: Int] = [:],
        keywordStats: [String: KeywordStat] = [:],
        invoiceCount: Int = 0
    ) {
        self.vendorId = vendorId
        self.displayName = displayName
        self.normalizedName = Self.normalize(displayName)
        self.nip = nip
        self.regon = regon
        self.payDueKeywords = payDueKeywords
        self.dueDateKeywords = dueDateKeywords
        self.totalKeywords = totalKeywords
        self.negativeKeywords = negativeKeywords
        self.preferredRegionForAmount = preferredRegionForAmount
        self.preferredRegionForDueDate = preferredRegionForDueDate
        self.weightsOverrides = weightsOverrides
        self.keywordStats = keywordStats
        self.invoiceCount = invoiceCount
        self.lastUpdated = Date()
        self.createdAt = Date()
    }

    // MARK: - Helpers

    /// Normalize name for fuzzy matching (lowercase, no diacritics, no spaces)
    static func normalize(_ name: String) -> String {
        return name
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    /// Get combined keywords (vendor + global fallback)
    func getEffectivePayDueKeywords(globalKeywords: [String]) -> [String] {
        return payDueKeywords.isEmpty ? globalKeywords : payDueKeywords + globalKeywords
    }

    func getEffectiveDueDateKeywords(globalKeywords: [String]) -> [String] {
        return dueDateKeywords.isEmpty ? globalKeywords : dueDateKeywords + globalKeywords
    }

    func getEffectiveTotalKeywords(globalKeywords: [String]) -> [String] {
        return totalKeywords.isEmpty ? globalKeywords : totalKeywords + globalKeywords
    }

    func getEffectiveNegativeKeywords(globalKeywords: [String]) -> [String] {
        return negativeKeywords.isEmpty ? globalKeywords : negativeKeywords + globalKeywords
    }
}

/// Statistics for a keyword (hits vs misses)
struct KeywordStat: Codable {
    var hits: Int       // Times this keyword was near the CORRECT value
    var misses: Int     // Times this keyword was near an INCORRECT value

    init(hits: Int = 0, misses: Int = 0) {
        self.hits = hits
        self.misses = misses
    }

    /// Should this keyword be promoted to permanent?
    /// Rule: hits >= 3 and misses == 0
    var shouldPromote: Bool {
        return hits >= 3 && misses == 0
    }

    /// Should this keyword be added to negativeKeywords?
    /// Rule: misses >= 3 and hits == 0
    var shouldDemote: Bool {
        return misses >= 3 && hits == 0
    }
}
