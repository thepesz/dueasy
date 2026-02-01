import Foundation
import SwiftData
import os.log

/// Service for managing vendor profiles and keyword learning
@MainActor
final class VendorProfileService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "VendorProfile")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Vendor Lookup

    /// Find vendor profile by name and/or tax ID
    func findVendorProfile(vendorName: String?, nip: String?, regon: String?) async throws -> VendorProfileV2? {
        logger.info("Finding vendor profile: name=\(vendorName ?? "nil"), nip=\(nip ?? "nil"), regon=\(regon ?? "nil")")

        // Strategy 1: Match by NIP (most reliable)
        if let nip = nip?.trimmingCharacters(in: .whitespaces), !nip.isEmpty {
            let descriptor = FetchDescriptor(predicate: VendorProfileV2.byNIP(nip))
            if let profile = try modelContext.fetch(descriptor).first {
                logger.info("Found vendor by NIP: \(profile.displayName)")
                return profile
            }
        }

        // Strategy 2: Match by REGON
        if let regon = regon?.trimmingCharacters(in: .whitespaces), !regon.isEmpty {
            let descriptor = FetchDescriptor(predicate: VendorProfileV2.byREGON(regon))
            if let profile = try modelContext.fetch(descriptor).first {
                logger.info("Found vendor by REGON: \(profile.displayName)")
                return profile
            }
        }

        // Strategy 3: Fuzzy match by normalized name
        if let vendorName = vendorName?.trimmingCharacters(in: .whitespaces), !vendorName.isEmpty {
            // Generate vendor key for exact match first
            let vendorKey = VendorProfileV2.generateVendorKey(name: vendorName, nip: nip)
            let keyDescriptor = FetchDescriptor(predicate: VendorProfileV2.byKey(vendorKey))
            if let profile = try modelContext.fetch(keyDescriptor).first {
                logger.info("Found vendor by exact key match: \(profile.displayName)")
                return profile
            }

            // Fallback: fuzzy match by name similarity
            let allProfiles = try modelContext.fetch(FetchDescriptor<VendorProfileV2>())
            let normalizedInput = vendorName
                .lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ".", with: "")

            let matches = allProfiles.filter { profile in
                let normalizedProfile = profile.displayName
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ".", with: "")
                let similarity = stringSimilarity(normalizedInput, normalizedProfile)
                return similarity > 0.8 // 80% similarity threshold
            }

            if let bestMatch = matches.first {
                logger.info("Found vendor by fuzzy name match: \(bestMatch.displayName) (similarity > 0.8)")
                return bestMatch
            }
        }

        logger.info("No vendor profile found")
        return nil
    }

    /// Get or create vendor profile
    func getOrCreateVendorProfile(
        vendorName: String,
        nip: String? = nil,
        regon: String? = nil,
        baseGlobalVersion: Int
    ) async throws -> VendorProfileV2 {
        // Try to find existing profile
        if let existing = try await findVendorProfile(vendorName: vendorName, nip: nip, regon: regon) {
            return existing
        }

        // Create new profile
        logger.info("Creating new vendor profile: \(vendorName)")
        let vendorKey = VendorProfileV2.generateVendorKey(name: vendorName, nip: nip)
        let newProfile = VendorProfileV2(
            vendorKey: vendorKey,
            displayName: vendorName,
            nip: nip,
            regon: regon,
            source: .autoLearned,
            baseGlobalVersion: baseGlobalVersion
        )

        modelContext.insert(newProfile)
        try modelContext.save()

        return newProfile
    }

    // MARK: - Keyword Learning

    /// Update vendor profile based on user correction
    /// Called after user saves a document with corrections
    func learnFromCorrection(
        vendorProfile: VendorProfileV2,
        correctedField: FieldType,
        correctContext: String,
        incorrectContexts: [String]
    ) async throws {
        logger.info("Learning from correction for vendor: \(vendorProfile.displayName), field: \(correctedField.rawValue)")

        // Extract keywords from correct context (2-3 word phrases)
        let correctKeywords = extractKeywords(from: correctContext)
        logger.debug("Correct context keywords: \(correctKeywords.joined(separator: ", "))")

        // Extract keywords from incorrect contexts
        var incorrectKeywords: Set<String> = []
        for context in incorrectContexts {
            incorrectKeywords.formUnion(extractKeywords(from: context))
        }
        logger.debug("Incorrect context keywords: \(incorrectKeywords.joined(separator: ", "))")

        // Update KeywordStats for each keyword
        for keyword in correctKeywords {
            try await updateKeywordStat(
                vendorKey: vendorProfile.vendorKey,
                phrase: keyword,
                fieldType: correctedField,
                isHit: true
            )
        }

        for keyword in incorrectKeywords {
            // Only count as miss if it wasn't also in correct context
            if !correctKeywords.contains(keyword) {
                try await updateKeywordStat(
                    vendorKey: vendorProfile.vendorKey,
                    phrase: keyword,
                    fieldType: correctedField,
                    isHit: false
                )
            }
        }

        // Sync promoted keywords to vendor profile
        try await syncPromotedKeywords(vendorProfile: vendorProfile, fieldType: correctedField)

        // Update vendor metadata
        vendorProfile.updatedAt = Date()

        try modelContext.save()
        logger.info("Vendor profile updated successfully")
    }

    /// Extract 2-3 word keywords from context
    private func extractKeywords(from context: String) -> [String] {
        let normalized = context
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        var keywords: Set<String> = []

        let words = normalized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0.count >= 3 } // At least 3 characters

        // Extract 2-word phrases
        for i in 0..<words.count - 1 {
            let phrase = "\(words[i]) \(words[i+1])"
            if phrase.count >= 6 && phrase.count <= 30 {
                keywords.insert(phrase)
            }
        }

        // Extract 3-word phrases
        for i in 0..<words.count - 2 {
            let phrase = "\(words[i]) \(words[i+1]) \(words[i+2])"
            if phrase.count >= 9 && phrase.count <= 40 {
                keywords.insert(phrase)
            }
        }

        return Array(keywords)
    }

    /// Update keyword statistics using KeywordStats model
    private func updateKeywordStat(
        vendorKey: String,
        phrase: String,
        fieldType: FieldType,
        isHit: Bool
    ) async throws {
        // Find existing KeywordStats or create new one
        let fieldTypeRaw = fieldType.rawValue
        let predicate = #Predicate<KeywordStats> { stat in
            stat.vendorKey == vendorKey && stat.phrase == phrase && stat.fieldTypeRaw == fieldTypeRaw
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        let existingStats = try modelContext.fetch(descriptor)

        if let stats = existingStats.first {
            // Update existing stats
            if isHit {
                stats.recordHit()
            } else {
                stats.recordMiss()
            }
            logger.debug("Updated KeywordStats '\(phrase)': hits=\(stats.hits), misses=\(stats.misses), state=\(stats.state.rawValue)")
        } else {
            // Create new KeywordStats
            let newStats = KeywordStats(
                vendorKey: vendorKey,
                phrase: phrase,
                fieldType: fieldType,
                hits: isHit ? 1 : 0,
                misses: isHit ? 0 : 1
            )
            modelContext.insert(newStats)
            logger.debug("Created new KeywordStats for '\(phrase)' (vendorKey: \(vendorKey))")
        }
    }

    /// Sync promoted keywords from KeywordStats to VendorProfileV2.keywordOverrides
    private func syncPromotedKeywords(vendorProfile: VendorProfileV2, fieldType: FieldType) async throws {
        // Fetch promoted keywords for this vendor and field type
        let vendorKey = vendorProfile.vendorKey
        let fieldTypeRaw = fieldType.rawValue
        let predicate = #Predicate<KeywordStats> { stat in
            stat.vendorKey == vendorKey &&
            stat.fieldTypeRaw == fieldTypeRaw &&
            stat.stateRaw == "promoted"
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let promotedStats = try modelContext.fetch(descriptor)

        // Convert to KeywordRules
        let promotedRules = promotedStats.map { stat in
            KeywordRule(phrase: stat.phrase, weight: 100, matchType: .contains)
        }

        // Update vendor profile overrides
        var overrides = vendorProfile.keywordOverrides

        switch fieldType {
        case .amount:
            // Merge with existing payDue keywords, avoiding duplicates
            let existingPhrases = Set(overrides.payDue.map { $0.phrase })
            let newRules = promotedRules.filter { !existingPhrases.contains($0.phrase) }
            overrides = VendorKeywordOverrides(
                payDue: overrides.payDue + newRules,
                dueDate: overrides.dueDate,
                total: overrides.total,
                negative: overrides.negative,
                disabledGlobalPhrases: overrides.disabledGlobalPhrases
            )
            logger.info("✅ Synced \(newRules.count) promoted keywords to payDue for vendor: \(vendorProfile.displayName)")

        case .dueDate:
            // Merge with existing dueDate keywords
            let existingPhrases = Set(overrides.dueDate.map { $0.phrase })
            let newRules = promotedRules.filter { !existingPhrases.contains($0.phrase) }
            overrides = VendorKeywordOverrides(
                payDue: overrides.payDue,
                dueDate: overrides.dueDate + newRules,
                total: overrides.total,
                negative: overrides.negative,
                disabledGlobalPhrases: overrides.disabledGlobalPhrases
            )
            logger.info("✅ Synced \(newRules.count) promoted keywords to dueDate for vendor: \(vendorProfile.displayName)")

        case .vendor, .documentNumber, .nip, .bankAccount:
            // Not applicable
            break
        }

        vendorProfile.keywordOverrides = overrides

        // Also check for blocked keywords and add to negative
        let blockedPredicate = #Predicate<KeywordStats> { stat in
            stat.vendorKey == vendorKey &&
            stat.stateRaw == "blocked"
        }
        let blockedDescriptor = FetchDescriptor(predicate: blockedPredicate)
        let blockedStats = try modelContext.fetch(blockedDescriptor)

        if !blockedStats.isEmpty {
            let blockedRules = blockedStats.map { stat in
                KeywordRule(phrase: stat.phrase, weight: -100, matchType: .contains)
            }
            let existingNegativePhrases = Set(overrides.negative.map { $0.phrase })
            let newNegativeRules = blockedRules.filter { !existingNegativePhrases.contains($0.phrase) }

            overrides = VendorKeywordOverrides(
                payDue: overrides.payDue,
                dueDate: overrides.dueDate,
                total: overrides.total,
                negative: overrides.negative + newNegativeRules,
                disabledGlobalPhrases: overrides.disabledGlobalPhrases
            )
            vendorProfile.keywordOverrides = overrides
            logger.info("⛔️ Synced \(newNegativeRules.count) blocked keywords to negative for vendor: \(vendorProfile.displayName)")
        }
    }

    // MARK: - Get Candidates

    /// Get vendor suggestions from top of document (for user selection)
    func getVendorSuggestions(
        from ocrText: String,
        lines: [String]
    ) -> [VendorSuggestion] {
        // Take top 25% of document
        let topLinesCount = max(5, lines.count / 4)
        let topLines = Array(lines.prefix(topLinesCount))
        let topText = topLines.joined(separator: "\n")

        var candidates: [VendorSuggestion] = []

        // Extract potential vendor names (company patterns)
        let companyPatterns = [
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:Sp\.\s*z\s*o\.?\s*o\.?|SP\.\s*Z\s*O\.?\s*O\.?))"#, "Sp. z o.o."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:S\.A\.|s\.a\.|SA))"#, "S.A."),
            (#"([A-ZĄĆĘŁŃÓŚŹŻ][A-Za-ząćęłńóśźż\s\-\.]+(?:Ltd\.?|LLC|Inc\.?|GmbH))"#, "Ltd/LLC"),
        ]

        for (pattern, _) in companyPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(topText.startIndex..., in: topText)
                let matches = regex.matches(in: topText, options: [], range: range)

                for match in matches {
                    if let nameRange = Range(match.range(at: 1), in: topText) {
                        let name = String(topText[nameRange]).trimmingCharacters(in: .whitespaces)
                        if name.count >= 3 && name.count <= 100 {
                            candidates.append(VendorSuggestion(
                                name: name,
                                nip: extractNIP(from: topText, near: name),
                                regon: extractREGON(from: topText, near: name),
                                confidence: 0.8
                            ))
                        }
                    }
                }
            }
        }

        // Deduplicate by normalized name
        var seen: Set<String> = []
        return candidates.filter { candidate in
            let normalized = VendorProfile.normalize(candidate.name)
            if seen.contains(normalized) {
                return false
            }
            seen.insert(normalized)
            return true
        }
    }

    /// Extract NIP (Polish Tax ID) from text near vendor name
    /// Format: NIP: 123-456-78-90 or NIP 1234567890
    private func extractNIP(from text: String, near vendorName: String) -> String? {
        // Look for NIP pattern: 10 digits with optional dashes/spaces
        let nipPattern = #"NIP[:\s]*(\d{3}[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}|\d{10})"#

        guard let regex = try? NSRegularExpression(pattern: nipPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let nipRange = Range(match.range(at: 1), in: text) {
            let nip = String(text[nipRange])
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
            return nip.count == 10 ? nip : nil
        }

        return nil
    }

    /// Extract REGON (Polish Business Registry Number) from text
    /// Format: REGON: 123456789 (9 digits) or 12345678901234 (14 digits)
    private func extractREGON(from text: String, near vendorName: String) -> String? {
        let regonPattern = #"REGON[:\s]*(\d{9}|\d{14})"#

        guard let regex = try? NSRegularExpression(pattern: regonPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let regonRange = Range(match.range(at: 1), in: text) {
            let regon = String(text[regonRange])
            return (regon.count == 9 || regon.count == 14) ? regon : nil
        }

        return nil
    }

    // MARK: - Helpers

    /// Calculate string similarity (Levenshtein distance normalized)
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let len1 = s1.count
        let len2 = s2.count

        if len1 == 0 || len2 == 0 {
            return 0.0
        }

        let maxLen = max(len1, len2)
        let distance = levenshteinDistance(s1, s2)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    /// Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        let len1 = s1.count
        let len2 = s2.count

        var dp = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)

        for i in 0...len1 {
            dp[i][0] = i
        }
        for j in 0...len2 {
            dp[0][j] = j
        }

        for i in 1...len1 {
            for j in 1...len2 {
                if s1[i-1] == s2[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]) + 1
                }
            }
        }

        return dp[len1][len2]
    }
}

/// Vendor suggestion for user selection (when multiple vendors detected)
struct VendorSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let nip: String?
    let regon: String?
    let confidence: Double
}

// MARK: - Vendor Profile Migration Service

/// Service for managing vendor profile migrations when global keyword config is updated
@MainActor
final class VendorProfileMigrationService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dueasy.app", category: "VendorMigration")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Migration Check

    /// Check and migrate all vendor profiles to the latest global keyword config version
    /// Call this on app startup after loading GlobalKeywordConfig
    func migrateVendorsIfNeeded(to globalConfig: GlobalKeywordConfig) async throws {
        let targetVersion = globalConfig.version

        logger.info("Checking for vendor migrations to global version \(targetVersion)")

        // Find all vendors that need migration
        let descriptor = FetchDescriptor(predicate: VendorProfileV2.needsMigration(toVersion: targetVersion))
        let vendorsToMigrate = try modelContext.fetch(descriptor)

        if vendorsToMigrate.isEmpty {
            logger.info("No vendors need migration - all up to date")
            return
        }

        logger.info("Found \(vendorsToMigrate.count) vendors to migrate")

        var migratedCount = 0
        var failedCount = 0

        for vendor in vendorsToMigrate {
            do {
                try await migrateVendor(vendor, to: globalConfig)
                migratedCount += 1
            } catch {
                logger.error("Failed to migrate vendor '\(vendor.displayName)': \(error.localizedDescription)")
                failedCount += 1
            }
        }

        try modelContext.save()

        logger.info("Migration complete: \(migratedCount) succeeded, \(failedCount) failed")
    }

    // MARK: - Individual Migration

    /// Migrate a single vendor profile to a new global config version
    private func migrateVendor(_ vendor: VendorProfileV2, to globalConfig: GlobalKeywordConfig) async throws {
        let oldVersion = vendor.baseGlobalVersion
        let newVersion = globalConfig.version

        logger.info("Migrating vendor '\(vendor.displayName)' from v\(oldVersion) to v\(newVersion)")

        // Check if migration is needed
        guard vendor.shouldMigrateTo(globalVersion: newVersion) else {
            logger.debug("Vendor '\(vendor.displayName)' is already at version \(newVersion)")
            return
        }

        // Perform soft migration (preserves vendor overrides)
        vendor.migrateToGlobalVersion(newVersion)

        logger.info("✅ Successfully migrated vendor '\(vendor.displayName)' to v\(newVersion)")
    }

    // MARK: - Rollback

    /// Rollback a vendor to its last good global version if accuracy dropped
    func rollbackVendorIfNeeded(_ vendor: VendorProfileV2, currentAccuracy: Double, threshold: Double = 0.7) throws {
        guard let stats = vendor.stats else {
            logger.debug("No stats available for vendor '\(vendor.displayName)' - skipping rollback check")
            return
        }

        let accuracyRate = stats.accuracyRate

        logger.debug("Vendor '\(vendor.displayName)' accuracy: \(accuracyRate) (threshold: \(threshold))")

        if accuracyRate < threshold && vendor.lastGoodGlobalVersion != nil {
            logger.warning("Vendor '\(vendor.displayName)' accuracy (\(accuracyRate)) below threshold (\(threshold)) - rolling back")
            vendor.rollbackToLastGoodVersion()
            try modelContext.save()
            logger.info("✅ Rolled back vendor '\(vendor.displayName)' to last good version")
        }
    }

    /// Batch rollback check for all vendors with low accuracy
    func checkAndRollbackLowAccuracyVendors(threshold: Double = 0.7) async throws {
        logger.info("Checking for vendors with accuracy below \(threshold)")

        // Fetch all vendors
        let allVendors = try modelContext.fetch(FetchDescriptor<VendorProfileV2>())

        var rolledBackCount = 0

        for vendor in allVendors {
            guard let stats = vendor.stats else { continue }

            let accuracyRate = stats.accuracyRate

            if accuracyRate < threshold && vendor.lastGoodGlobalVersion != nil {
                logger.warning("Vendor '\(vendor.displayName)' has low accuracy (\(accuracyRate)) - rolling back")
                vendor.rollbackToLastGoodVersion()
                rolledBackCount += 1
            }
        }

        if rolledBackCount > 0 {
            try modelContext.save()
            logger.info("Rolled back \(rolledBackCount) vendors due to low accuracy")
        } else {
            logger.info("No vendors needed rollback")
        }
    }

    // MARK: - Statistics

    /// Get migration statistics for monitoring
    func getMigrationStats() throws -> MigrationStats {
        let allVendors = try modelContext.fetch(FetchDescriptor<VendorProfileV2>())

        let versionCounts = Dictionary(grouping: allVendors) { $0.baseGlobalVersion }
            .mapValues { $0.count }

        let totalVendors = allVendors.count
        let vendorsWithRollback = allVendors.filter { $0.lastGoodGlobalVersion != nil }.count
        let lowAccuracyVendors = allVendors.filter { vendor in
            guard let stats = vendor.stats else { return false }
            return stats.accuracyRate < 0.7
        }.count

        return MigrationStats(
            totalVendors: totalVendors,
            versionCounts: versionCounts,
            vendorsWithRollback: vendorsWithRollback,
            lowAccuracyVendors: lowAccuracyVendors
        )
    }
}

// MARK: - Migration Statistics

struct MigrationStats: Codable {
    let totalVendors: Int
    let versionCounts: [Int: Int]  // version -> count
    let vendorsWithRollback: Int
    let lowAccuracyVendors: Int

    var mostCommonVersion: Int? {
        versionCounts.max(by: { $0.value < $1.value })?.key
    }
}
