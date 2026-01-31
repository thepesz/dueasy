import Foundation
import SwiftData

/// Enhanced Vendor Profile with versioning and proper keyword management
/// This replaces the simpler VendorProfile.swift
@Model
final class VendorProfileV2 {

    // MARK: - Identity

    @Attribute(.unique) var id: UUID

    /// Stable vendor key (e.g., "orange_pl", "pge_pl", or hash of name+NIP)
    /// Used for linking KeywordStats and ensuring uniqueness
    @Attribute(.unique) var vendorKey: String

    /// Display name for UI
    var displayName: String

    // Tax identifiers for matching
    var nip: String?            // Polish Tax ID (10 digits)
    var regon: String?          // Polish Business Registry (9 or 14 digits)

    // MARK: - Source and Versioning

    /// How was this profile created
    var sourceRaw: String

    /// Base global version this vendor was created with
    var baseGlobalVersion: Int

    /// Last known good global version (for rollback if accuracy drops)
    var lastGoodGlobalVersion: Int?

    // MARK: - Keyword Overrides

    /// Vendor-specific keyword overrides (supplement/replace global)
    @Attribute(.externalStorage)
    var keywordOverrides: VendorKeywordOverrides

    // MARK: - Layout Hints

    /// Optional layout preferences (where fields typically appear)
    @Attribute(.externalStorage)
    var layoutHints: LayoutHints?

    // MARK: - Statistics

    /// Performance statistics
    @Attribute(.externalStorage)
    var stats: VendorStats?

    // MARK: - Metadata

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var source: VendorProfileSource {
        get { VendorProfileSource(rawValue: sourceRaw) ?? .autoLearned }
        set { sourceRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        vendorKey: String,
        displayName: String,
        nip: String? = nil,
        regon: String? = nil,
        source: VendorProfileSource = .autoLearned,
        baseGlobalVersion: Int = 1,
        keywordOverrides: VendorKeywordOverrides = .empty,
        layoutHints: LayoutHints? = nil,
        stats: VendorStats? = nil
    ) {
        self.id = id
        self.vendorKey = vendorKey
        self.displayName = displayName
        self.nip = nip
        self.regon = regon
        self.sourceRaw = source.rawValue
        self.baseGlobalVersion = baseGlobalVersion
        self.lastGoodGlobalVersion = nil
        self.keywordOverrides = keywordOverrides
        self.layoutHints = layoutHints
        self.stats = stats
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Vendor Key Generation

    /// Generate stable vendor key from name and NIP
    static func generateVendorKey(name: String, nip: String?) -> String {
        let normalizedName = name.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "")

        if let nip = nip {
            return "\(normalizedName)_\(nip)"
        } else {
            // Use hash of name if no NIP available
            let hash = normalizedName.hashValue
            return "\(normalizedName)_\(abs(hash))"
        }
    }

    // MARK: - Keyword Management

    /// Get effective keywords for a field, combining global + vendor overrides
    func getEffectiveKeywords(
        for fieldType: FieldType,
        globalConfig: GlobalKeywordConfig
    ) -> [KeywordRule] {
        let globalKeywords = globalConfig.getKeywords(for: fieldType)
        let vendorKeywords: [KeywordRule]

        switch fieldType {
        case .amount:
            vendorKeywords = keywordOverrides.payDue + keywordOverrides.total
        case .dueDate:
            vendorKeywords = keywordOverrides.dueDate
        case .vendor, .documentNumber:
            vendorKeywords = []
        }

        // Filter out disabled global phrases
        let disabledSet = Set(keywordOverrides.disabledGlobalPhrases)
        let enabledGlobalKeywords = globalKeywords.filter { rule in
            !disabledSet.contains(rule.phrase)
        }

        // Vendor keywords take precedence, then enabled global keywords
        return vendorKeywords + enabledGlobalKeywords
    }

    /// Calculate score using vendor + global keywords
    func calculateScore(
        for fieldType: FieldType,
        context: String,
        globalConfig: GlobalKeywordConfig
    ) -> (score: Int, matchedRules: [KeywordRule]) {
        let keywords = getEffectiveKeywords(for: fieldType, globalConfig: globalConfig)
        let negativeKeywords = keywordOverrides.negative.isEmpty
            ? globalConfig.negativeKeywords
            : keywordOverrides.negative

        let allKeywords = keywords + negativeKeywords
        var totalScore = 0
        var matched: [KeywordRule] = []

        for rule in allKeywords {
            if rule.matches(context) {
                totalScore += rule.weight
                matched.append(rule)
            }
        }

        return (totalScore, matched)
    }

    // MARK: - Versioning and Migration

    /// Check if this vendor should be migrated to a new global version
    func shouldMigrateTo(globalVersion: Int) -> Bool {
        return globalVersion > baseGlobalVersion
    }

    /// Migrate to new global version (soft migration - keep overrides)
    func migrateToGlobalVersion(_ newVersion: Int) {
        // Save current version as last good version
        lastGoodGlobalVersion = baseGlobalVersion

        // Update base version
        baseGlobalVersion = newVersion
        updatedAt = Date()
    }

    /// Rollback to last good global version (if accuracy dropped)
    func rollbackToLastGoodVersion() {
        if let lastGood = lastGoodGlobalVersion {
            baseGlobalVersion = lastGood
            lastGoodGlobalVersion = nil
            updatedAt = Date()
        }
    }

    // MARK: - Statistics Updates

    /// Record successful extraction
    func recordSuccess() {
        var currentStats = stats ?? VendorStats()
        currentStats.totalInvoices += 1
        currentStats.successfulExtractions += 1
        stats = currentStats
        updatedAt = Date()
    }

    /// Record user correction
    func recordCorrection(accuracyScore: Double) {
        var currentStats = stats ?? VendorStats()
        currentStats.totalInvoices += 1
        currentStats.userCorrections += 1
        currentStats.lastAccuracyScore = accuracyScore
        stats = currentStats
        updatedAt = Date()
    }
}

// MARK: - Querying Helpers

extension VendorProfileV2 {

    /// Predicate for finding vendor by key
    static func byKey(_ vendorKey: String) -> Predicate<VendorProfileV2> {
        #Predicate<VendorProfileV2> { profile in
            profile.vendorKey == vendorKey
        }
    }

    /// Predicate for finding vendor by NIP
    static func byNIP(_ nip: String) -> Predicate<VendorProfileV2> {
        #Predicate<VendorProfileV2> { profile in
            profile.nip == nip
        }
    }

    /// Predicate for finding vendor by REGON
    static func byREGON(_ regon: String) -> Predicate<VendorProfileV2> {
        #Predicate<VendorProfileV2> { profile in
            profile.regon == regon
        }
    }

    /// Predicate for finding vendors that need migration
    static func needsMigration(toVersion version: Int) -> Predicate<VendorProfileV2> {
        #Predicate<VendorProfileV2> { profile in
            profile.baseGlobalVersion < version
        }
    }
}
