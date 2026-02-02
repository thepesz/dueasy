import Foundation
import SwiftData
import os.log

/// Service for auto-detecting recurring payment patterns.
/// Analyzes vendor document history and generates suggestions when confidence is high.
///
/// Detection rules (applied in order):
/// 1. Rule 0: Skip if RecurringTemplate already exists for vendor
/// 2. Time eligibility: First document >= 60 days ago OR 3+ documents spanning 45+ days
/// 3. Category gate: Recurring-friendly ratio >= 70%, hard-reject ratio low
/// 4. Due date stability: StdDev <= 3 days OR dominant day bucket >= 70%
/// 5. Strong signal: Stable IBAN OR recurring keywords OR amount stability
/// 6. Confidence threshold: Score >= 0.75 to show suggestion
protocol RecurringDetectionServiceProtocol: Sendable {
    /// Analyzes a vendor's document history and updates or creates a RecurringCandidate.
    /// - Parameters:
    ///   - vendorFingerprint: The vendor fingerprint
    ///   - vendorName: Display name for the vendor
    /// - Returns: Updated or created candidate (nil if template already exists)
    func analyzeVendor(
        vendorFingerprint: String,
        vendorName: String
    ) async throws -> RecurringCandidate?

    /// Fetches all candidates that should be shown as suggestions.
    /// - Returns: Array of candidates meeting suggestion criteria
    func fetchSuggestionCandidates() async throws -> [RecurringCandidate]

    /// Dismisses a candidate suggestion.
    /// - Parameter candidate: The candidate to dismiss
    func dismissCandidate(_ candidate: RecurringCandidate) async throws

    /// Snoozes a candidate suggestion (will be shown again later).
    /// - Parameter candidate: The candidate to snooze
    func snoozeCandidate(_ candidate: RecurringCandidate) async throws

    /// Runs detection analysis for all vendors that might be eligible.
    /// Call periodically (e.g., on app launch or after document save).
    /// - Returns: Number of candidates updated
    func runDetectionAnalysis() async throws -> Int
}

/// Default implementation of RecurringDetectionService
@MainActor
final class RecurringDetectionService: RecurringDetectionServiceProtocol {

    private let modelContext: ModelContext
    private let templateService: RecurringTemplateServiceProtocol
    private let classifierService: DocumentClassifierServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringDetection")

    /// Minimum confidence score to show suggestion
    private static let suggestionThreshold = 0.75

    /// Days for snooze period
    private static let snoozeDays = 14

    init(
        modelContext: ModelContext,
        templateService: RecurringTemplateServiceProtocol,
        classifierService: DocumentClassifierServiceProtocol
    ) {
        self.modelContext = modelContext
        self.templateService = templateService
        self.classifierService = classifierService
    }

    // MARK: - Vendor Analysis

    func analyzeVendor(
        vendorFingerprint: String,
        vendorName: String
    ) async throws -> RecurringCandidate? {
        // Rule 0: Skip if template already exists
        if try await templateService.templateExists(forVendorFingerprint: vendorFingerprint) {
            logger.debug("Template already exists for vendor, skipping detection")
            return nil
        }

        // Fetch all documents for this vendor
        let documents = try await fetchDocuments(forVendorFingerprint: vendorFingerprint)

        guard documents.count >= 2 else {
            logger.debug("Not enough documents for vendor: \(documents.count)")
            return nil
        }

        // Get or create candidate
        var candidate = try await fetchCandidate(byVendorFingerprint: vendorFingerprint)
        if candidate == nil {
            candidate = RecurringCandidate(
                vendorFingerprint: vendorFingerprint,
                vendorDisplayName: vendorName
            )
            modelContext.insert(candidate!)
        }

        guard let candidate = candidate else { return nil }

        // Update candidate with analysis results
        try updateCandidateStatistics(candidate, from: documents)

        // Calculate confidence score
        let confidenceScore = calculateConfidenceScore(candidate, documents: documents)
        candidate.confidenceScore = confidenceScore

        try modelContext.save()

        // PRIVACY: Log only metrics, not vendor names or fingerprints
        logger.info("Analyzed vendor: confidence=\(String(format: "%.2f", confidenceScore)), documents=\(documents.count)")
        logger.debug("Candidate after save: confidence=\(candidate.confidenceScore), state=\(candidate.suggestionStateRaw), id=\(candidate.id)")

        return candidate
    }

    // MARK: - Candidate Queries

    func fetchSuggestionCandidates() async throws -> [RecurringCandidate] {
        logger.info("Fetching suggestion candidates (threshold: \(Self.suggestionThreshold))")

        // DIAGNOSTIC: Fetch ALL candidates to see what's in the database
        let allDescriptor = FetchDescriptor<RecurringCandidate>()
        let allCandidates = try modelContext.fetch(allDescriptor)
        // PRIVACY: Log only counts and metrics, not vendor names
        logger.info("Total candidates in database: \(allCandidates.count)")
        for candidate in allCandidates {
            logger.debug("Candidate: confidence=\(String(format: "%.2f", candidate.confidenceScore)), state=\(candidate.suggestionStateRaw), meetsThreshold=\(candidate.confidenceScore >= Self.suggestionThreshold)")
        }

        let threshold = Self.suggestionThreshold
        let descriptor = FetchDescriptor<RecurringCandidate>(
            predicate: #Predicate<RecurringCandidate> {
                $0.confidenceScore >= threshold &&
                ($0.suggestionStateRaw == "none" || $0.suggestionStateRaw == "suggested")
            },
            sortBy: [SortDescriptor(\.confidenceScore, order: .reverse)]
        )

        var candidates = try modelContext.fetch(descriptor)
        logger.info("Found \(candidates.count) candidates meeting confidence threshold (>= \(Self.suggestionThreshold))")

        // PRIVACY: Log only metrics, not vendor names
        for candidate in candidates {
            logger.debug("Candidate: confidence=\(String(format: "%.2f", candidate.confidenceScore)), state=\(candidate.suggestionStateRaw), daySpan=\(candidate.daySpan), timeEligible=\(candidate.isTimeEligible)")
        }

        // Filter by additional criteria that can't be expressed in predicate
        let beforeFilterCount = candidates.count
        candidates = candidates.filter { candidate in
            // Must be time-eligible
            guard candidate.isTimeEligible else {
                logger.debug("Filtering out candidate: not time-eligible, docs=\(candidate.documentCount), span=\(candidate.daySpan)")
                return false
            }

            // Must not be hard-rejected category
            guard !candidate.documentCategory.isHardRejectedForAutoDetection else {
                logger.debug("Filtering out candidate: hard-rejected category (\(candidate.documentCategoryRaw))")
                return false
            }

            // If snoozed, check if snooze period has passed
            if candidate.suggestionState == .suggested,
               let lastSuggested = candidate.lastSuggestedAt {
                let daysSinceSuggestion = Calendar.current.dateComponents(
                    [.day],
                    from: lastSuggested,
                    to: Date()
                ).day ?? 0

                // Don't show again too soon
                if daysSinceSuggestion < 7 {
                    logger.debug("Filtering out candidate: suggested too recently (\(daysSinceSuggestion) days ago)")
                    return false
                }
            }

            return true
        }

        logger.info("After filtering: \(candidates.count) candidates (filtered out \(beforeFilterCount - candidates.count))")

        return candidates
    }

    func fetchCandidate(byVendorFingerprint vendorFingerprint: String) async throws -> RecurringCandidate? {
        let descriptor = FetchDescriptor<RecurringCandidate>(
            predicate: #Predicate<RecurringCandidate> { $0.vendorFingerprint == vendorFingerprint }
        )
        let candidates = try modelContext.fetch(descriptor)
        return candidates.first
    }

    // MARK: - Candidate Actions

    func dismissCandidate(_ candidate: RecurringCandidate) async throws {
        candidate.dismiss()
        try modelContext.save()
        // PRIVACY: Log only metrics, not vendor names
        logger.info("Dismissed recurring candidate: confidence=\(String(format: "%.2f", candidate.confidenceScore)), docs=\(candidate.documentCount)")
    }

    func snoozeCandidate(_ candidate: RecurringCandidate) async throws {
        // Reset to "none" state so it can be suggested again later
        candidate.resetSuggestionState()
        try modelContext.save()
        // PRIVACY: Log only metrics, not vendor names
        logger.info("Snoozed recurring candidate: confidence=\(String(format: "%.2f", candidate.confidenceScore)), docs=\(candidate.documentCount)")
    }

    // MARK: - Batch Analysis

    func runDetectionAnalysis() async throws -> Int {
        logger.info("=== RECURRING DETECTION ANALYSIS START ===")

        // Find all vendors with 2+ documents that don't have templates
        let vendorGroups = try await findVendorsForAnalysis()

        logger.info("Found \(vendorGroups.count) vendors with 2+ documents for analysis")

        var updatedCount = 0
        var skippedTemplateExists = 0
        var skippedNoPattern = 0

        for (fingerprint, documents) in vendorGroups {
            guard let firstDoc = documents.first else { continue }

            // PRIVACY: Log only metrics, not vendor names or dates
            logger.debug("Analyzing vendor group: docs=\(documents.count), fingerprint=\(fingerprint.prefix(8))...")

            // Check if template exists (skip if so)
            if try await templateService.templateExists(forVendorFingerprint: fingerprint) {
                logger.debug("SKIPPED: Template already exists")
                skippedTemplateExists += 1
                continue
            }

            // Analyze this vendor
            if let candidate = try await analyzeVendor(
                vendorFingerprint: fingerprint,
                vendorName: firstDoc.title
            ) {
                // PRIVACY: Log only metrics
                logger.info("Candidate created/updated: confidence=\(String(format: "%.2f", candidate.confidenceScore)), timeEligible=\(candidate.isTimeEligible), category=\(candidate.documentCategoryRaw)")
                logger.debug("Details: dominantDay=\(candidate.dominantDueDayOfMonth ?? -1), daySpan=\(candidate.daySpan), state=\(candidate.suggestionStateRaw)")

                if !candidate.isTimeEligible {
                    logger.debug("Not time eligible: docs=\(candidate.documentCount), span=\(candidate.daySpan)")
                }

                updatedCount += 1
            } else {
                logger.debug("SKIPPED: No pattern detected")
                skippedNoPattern += 1
            }
        }

        logger.info("=== RECURRING DETECTION ANALYSIS COMPLETE ===")
        logger.info("Summary:")
        logger.info("  - Vendors analyzed: \(vendorGroups.count)")
        logger.info("  - Candidates updated: \(updatedCount)")
        logger.info("  - Skipped (template exists): \(skippedTemplateExists)")
        logger.info("  - Skipped (no pattern): \(skippedNoPattern)")

        return updatedCount
    }

    // MARK: - Private Helpers

    private func fetchDocuments(forVendorFingerprint fingerprint: String) async throws -> [FinanceDocument] {
        // Fetch all documents for this vendor
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.vendorFingerprint == fingerprint }
        )
        var documents = try modelContext.fetch(descriptor)

        // Sort by dueDate for pattern analysis (not createdAt)
        // This handles historical documents added later (e.g., Nov 2024 invoice added in Jan 2025)
        documents.sort { doc1, doc2 in
            let date1 = doc1.dueDate ?? doc1.createdAt
            let date2 = doc2.dueDate ?? doc2.createdAt
            return date1 < date2
        }

        return documents
    }

    private func findVendorsForAnalysis() async throws -> [String: [FinanceDocument]] {
        logger.debug("Finding vendors for analysis...")

        // Fetch all documents with vendor fingerprints
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.vendorFingerprint != nil }
        )
        let documents = try modelContext.fetch(descriptor)

        logger.info("Total documents with vendorFingerprint: \(documents.count)")

        // Also log documents WITHOUT fingerprints for debugging
        let noFingerprintDescriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.vendorFingerprint == nil }
        )
        let noFingerprintDocs = try modelContext.fetch(noFingerprintDescriptor)
        if !noFingerprintDocs.isEmpty {
            // PRIVACY: Log only count, not document titles
            logger.warning("Documents WITHOUT vendorFingerprint: \(noFingerprintDocs.count)")
        }

        // Group by vendor fingerprint
        var groups: [String: [FinanceDocument]] = [:]
        for doc in documents {
            guard let fingerprint = doc.vendorFingerprint else { continue }
            groups[fingerprint, default: []].append(doc)
        }

        logger.info("Unique vendors found: \(groups.count)")

        // Sort each group by dueDate for consistent pattern analysis
        for (fingerprint, docs) in groups {
            groups[fingerprint] = docs.sorted { doc1, doc2 in
                let date1 = doc1.dueDate ?? doc1.createdAt
                let date2 = doc2.dueDate ?? doc2.createdAt
                return date1 < date2
            }
        }

        // PRIVACY: Log only counts, not vendor names
        logger.debug("Vendor groups created: \(groups.count) unique vendors")

        // Filter to vendors with 2+ documents
        let eligible = groups.filter { $0.value.count >= 2 }
        logger.info("Vendors with 2+ documents (eligible for analysis): \(eligible.count)")

        return eligible
    }

    private func updateCandidateStatistics(_ candidate: RecurringCandidate, from documents: [FinanceDocument]) throws {
        guard let firstDoc = documents.first, let lastDoc = documents.last else { return }

        // Basic stats
        let documentCount = documents.count

        // Use dueDate for pattern analysis (handles historical data)
        // Documents are already sorted by dueDate from fetchDocuments
        let firstDueDate = firstDoc.dueDate ?? firstDoc.createdAt
        let lastDueDate = lastDoc.dueDate ?? lastDoc.createdAt

        // For time eligibility, use the earlier of:
        // - First document's dueDate (the actual billing date)
        // - First document's createdAt (when it was added)
        // This allows historical documents added recently to still be eligible
        let firstDate = firstDueDate
        let lastDate = lastDueDate

        // PRIVACY: Log only metrics, not actual dates (which can identify documents)
        logger.debug("Statistics update: docs=\(documentCount), hasDueDates=\(firstDoc.dueDate != nil && lastDoc.dueDate != nil)")

        // Classify documents
        let categoryResults = documents.compactMap { doc -> DocumentCategory? in
            let result = classifierService.classify(
                vendorName: doc.title,
                ocrText: nil,
                amount: doc.amount
            )
            return result.category
        }

        // Find dominant category
        let categoryCount = Dictionary(grouping: categoryResults, by: { $0 }).mapValues { $0.count }
        let dominantCategory = categoryCount.max(by: { $0.value < $1.value })?.key ?? .unknown

        // Due date analysis
        let dueDates = documents.compactMap { $0.dueDate }
        let dueDays = dueDates.map { Calendar.current.component(.day, from: $0) }

        let (dominantDay, dominantPercentage) = findDominantDay(dueDays)
        let stdDev = calculateStdDev(dueDays)

        // Calculate bucket stability ratio (+/-3 days tolerance)
        // This handles weekend/holiday shifts where vendor moves due date
        let bucketStabilityRatio = calculateDueDateBucketStability(dueDays: dueDays, dominantDay: dominantDay)

        // PRIVACY: Log only statistical metrics, not actual due dates
        logger.debug("Due date analysis: dominantDay=\(dominantDay ?? -1), dominantPct=\(String(format: "%.2f", dominantPercentage ?? 0)), stdDev=\(String(format: "%.2f", stdDev ?? -1)), bucketRatio=\(String(format: "%.2f", bucketStabilityRatio ?? 0))")

        // Amount analysis
        let amounts = documents.map { $0.amountValue }
        let avgAmount = amounts.isEmpty ? nil : amounts.reduce(0, +) / Double(amounts.count)
        let amountStdDev = calculateStdDev(amounts.map { Int($0) })
        let minAmount = amounts.min()
        let maxAmount = amounts.max()

        // IBAN stability
        let ibans = documents.compactMap { $0.bankAccountNumber }.filter { !$0.isEmpty }
        let uniqueIBANs = Set(ibans)
        let hasStableIBAN = uniqueIBANs.count == 1 && !ibans.isEmpty
        let stableIBAN = hasStableIBAN ? uniqueIBANs.first : nil

        // PRIVACY: Log only counts, not actual IBAN values
        logger.debug("IBAN analysis: found=\(ibans.count), unique=\(uniqueIBANs.count), isStable=\(hasStableIBAN)")

        // Recurring keywords check
        let hasRecurringKeywords = documents.contains { doc in
            let classifier = classifierService as? DocumentClassifierService
            return classifier?.hasRecurringKeywords(in: doc.title) ?? false
        }

        // Check for fallback fingerprint (no NIP)
        // A fingerprint is considered "fallback" if NONE of the documents have NIP extracted
        // This indicates the vendor might be foreign or OCR failed to extract NIP
        let documentsWithNIP = documents.filter { doc in
            guard let nip = doc.vendorNIP else { return false }
            return !nip.isEmpty
        }
        let hasFallbackFingerprint = documentsWithNIP.isEmpty

        logger.debug("Fallback fingerprint: \(hasFallbackFingerprint) (docsWithNIP=\(documentsWithNIP.count)/\(documents.count))")

        // Update candidate
        candidate.documentCategory = dominantCategory
        candidate.updateStatistics(
            documentCount: documentCount,
            firstDocumentDate: firstDate,
            lastDocumentDate: lastDate,
            dominantDueDayOfMonth: dominantDay,
            dominantDueDayPercentage: dominantPercentage,
            dueDateStdDev: stdDev,
            dueDateBucketStabilityRatio: bucketStabilityRatio,
            averageAmount: avgAmount != nil ? Decimal(avgAmount!) : nil,
            amountStdDev: amountStdDev,
            minAmount: minAmount != nil ? Decimal(minAmount!) : nil,
            maxAmount: maxAmount != nil ? Decimal(maxAmount!) : nil,
            hasStableIBAN: hasStableIBAN,
            stableIBAN: stableIBAN,
            hasRecurringKeywords: hasRecurringKeywords,
            hasFallbackFingerprint: hasFallbackFingerprint,
            confidenceScore: 0.0 // Will be calculated separately
        )

        // Log time eligibility calculation - PRIVACY: no actual dates
        let now = Date()
        let daysSinceFirst = Calendar.current.dateComponents([.day], from: candidate.firstDocumentDate, to: now).day ?? 0
        logger.debug("Time eligibility: daysSinceFirst=\(daysSinceFirst), daySpan=\(candidate.daySpan), docs=\(candidate.documentCount)")
    }

    /// Calculates the bucket stability ratio for due dates (+/-3 days tolerance).
    /// This handles weekend/holiday shifts where vendor moves due date by a few days.
    ///
    /// Example: If dominant day is 26, documents on days 23-29 are considered "in bucket"
    /// - 26 (Sat) -> moved to 28 (Mon) = still in bucket
    /// - 15 (holiday) -> moved to 16 = still in bucket
    ///
    /// Returns ratio of documents within +/-3 days of dominant day (0.0 to 1.0)
    private func calculateDueDateBucketStability(dueDays: [Int], dominantDay: Int?) -> Double? {
        guard let dominantDay = dominantDay, !dueDays.isEmpty else {
            return nil
        }

        // Count documents within +/-3 days of dominant day
        // Handle month wrap-around (e.g., day 30 vs day 2)
        let inBucket = dueDays.filter { day in
            let diff = abs(day - dominantDay)
            // Handle month boundary (e.g., day 30 and day 2 are 3 days apart at month boundary)
            let wrappedDiff = min(diff, 31 - diff)
            return wrappedDiff <= 3
        }.count

        let stabilityRatio = Double(inBucket) / Double(dueDays.count)

        logger.debug("      - Bucket calculation: dominantDay=\(dominantDay), inBucket=\(inBucket)/\(dueDays.count), ratio=\(String(format: "%.2f", stabilityRatio))")

        return stabilityRatio
    }

    private func calculateConfidenceScore(_ candidate: RecurringCandidate, documents: [FinanceDocument]) -> Double {
        // Factor 1: Time eligibility (required gate)
        guard candidate.isTimeEligible else {
            logger.debug("  Score: 0.0 (not time eligible)")
            return 0.0
        }

        // =========================================================================
        // SCORING APPROACH (v2 - Architect Feedback Refinements)
        // =========================================================================
        // Total possible: 1.0 (100%)
        // Threshold: 0.75 (75%)
        //
        // Weight Distribution:
        // - Category:     0.10 (reduced from 0.15 - soft filter, not hard block)
        // - Due Date:     0.35 (unchanged - most important signal)
        // - Count/Span:   0.20 (unchanged)
        // - Amount:       0.15 (unchanged)
        // - IBAN:         0.15 (increased from 0.10 - stronger signal)
        // - Keywords:     0.05 (unchanged)
        //
        // Key Changes:
        // 1. Due date uses bucketing (+/-3 days) for weekend/holiday tolerance
        // 2. Unknown/generic categories require strong signal gate
        // 3. Fallback fingerprint applies small penalty
        // =========================================================================

        var score = 0.0
        var scoreBreakdown: [String] = []

        // ---------------------------------------------------------------------
        // Factor 1: Category (max 0.10, reduced from 0.15)
        // - Hard block ONLY: fuel, grocery, retail, receipt (weight = 0.0)
        // - Unknown/generic: Soft filter with 0.5 weight (not blocked)
        // - Utility/telecom/rent/insurance: Full 1.0 weight
        // ---------------------------------------------------------------------
        let categoryWeight = candidate.documentCategory.recurringConfidenceWeight
        let categoryScore = categoryWeight * 0.10
        score += categoryScore
        scoreBreakdown.append("category: \(String(format: "%.3f", categoryScore)) (\(candidate.documentCategoryRaw), weight=\(categoryWeight))")

        // ---------------------------------------------------------------------
        // Factor 2: Due Date Consistency (max 0.35) - MOST IMPORTANT
        // Uses BUCKETING approach (+/-3 days tolerance) for stability ratio
        // This handles weekend/holiday shifts where vendor moves due date
        // ---------------------------------------------------------------------
        let dueDateScore = scoreDueDateConsistency(candidate: candidate, documents: documents)
        score += dueDateScore
        let stabilityRatio = candidate.dueDateBucketStabilityRatio ?? 0.0
        let stdDev = candidate.dueDateStdDev ?? -1
        scoreBreakdown.append("dueDate: \(String(format: "%.3f", dueDateScore)) (bucketRatio=\(String(format: "%.2f", stabilityRatio)), stdDev=\(String(format: "%.1f", stdDev)), dominantDay=\(candidate.dominantDueDayOfMonth ?? -1))")

        // ---------------------------------------------------------------------
        // Factor 3: Document Count and Span (max 0.20)
        // 3 documents with proper span is enough for a clear pattern
        // ---------------------------------------------------------------------
        var countScore = 0.0
        let docCount = candidate.documentCount
        let daySpan = candidate.daySpan

        if docCount >= 6 && daySpan >= 150 {
            countScore = 0.20
        } else if docCount >= 4 && daySpan >= 90 {
            countScore = 0.17
        } else if docCount >= 3 && daySpan >= 45 {
            // 3 monthly documents (e.g., Aug, Sep, Oct) = clear pattern
            countScore = 0.15
        } else if docCount >= 2 && daySpan >= 60 {
            countScore = 0.10
        } else if docCount >= 2 {
            countScore = 0.05
        }
        score += countScore
        scoreBreakdown.append("count: \(String(format: "%.3f", countScore)) (docs=\(docCount), span=\(daySpan)d)")

        // ---------------------------------------------------------------------
        // Factor 4: Amount Stability (max 0.15)
        // Uses coefficient of variation (stdDev / mean) to measure consistency
        // ---------------------------------------------------------------------
        var amountScore = 0.0
        var amountCoV: Double = -1
        if let amountStdDev = candidate.amountStdDev,
           let avgAmount = candidate.averageAmount,
           avgAmount > 0 {
            let avgDouble = NSDecimalNumber(decimal: avgAmount).doubleValue
            amountCoV = amountStdDev / avgDouble
            if amountCoV == 0 {
                amountScore = 0.15 // Identical amounts
            } else if amountCoV < 0.05 {
                amountScore = 0.13 // Very stable (<5% variation)
            } else if amountCoV < 0.10 {
                amountScore = 0.10 // Stable (<10% variation)
            } else if amountCoV < 0.25 {
                amountScore = 0.07 // Moderate (<25% variation)
            }
        }
        score += amountScore
        scoreBreakdown.append("amount: \(String(format: "%.3f", amountScore)) (CoV=\(String(format: "%.3f", amountCoV)))")

        // ---------------------------------------------------------------------
        // Factor 5: Stable IBAN (max 0.15, increased from 0.10)
        // IBAN is a very strong signal - bank account doesn't change for
        // recurring payments. Increased weight to reflect this.
        // ---------------------------------------------------------------------
        let ibanScore = candidate.hasStableIBAN ? 0.15 : 0.0
        score += ibanScore
        scoreBreakdown.append("iban: \(String(format: "%.3f", ibanScore)) (stable=\(candidate.hasStableIBAN))")

        // ---------------------------------------------------------------------
        // Factor 6: Recurring Keywords (max 0.05)
        // Keywords like "abonament", "miesieczna", "rata" indicate recurring
        // ---------------------------------------------------------------------
        let keywordScore = candidate.hasRecurringKeywords ? 0.05 : 0.0
        score += keywordScore
        scoreBreakdown.append("keywords: \(String(format: "%.3f", keywordScore)) (found=\(candidate.hasRecurringKeywords))")

        // ---------------------------------------------------------------------
        // Penalty: Fallback Fingerprint (-0.05)
        // If fingerprint was generated without NIP, apply small penalty
        // ---------------------------------------------------------------------
        let fingerprintPenalty: Double = candidate.hasFallbackFingerprint ? -0.05 : 0.0
        score += fingerprintPenalty
        if candidate.hasFallbackFingerprint {
            scoreBreakdown.append("fingerprintPenalty: \(String(format: "%.3f", fingerprintPenalty)) (no NIP)")
        }

        // ---------------------------------------------------------------------
        // Strong Signal Gate for Unknown/Generic Categories
        // If category is unknown or invoiceGeneric, require at least ONE strong signal
        // Otherwise cap confidence at 0.65 (below threshold) to prevent false positives
        // ---------------------------------------------------------------------
        var strongSignalGateApplied = false
        if candidate.documentCategory.requiresStrongSignalForRecurring {
            // Check for strong signals:
            // - Stable IBAN (score >= 0.12)
            // - Very stable amounts (amountScore >= 0.12)
            // - Recurring keywords (keywordScore >= 0.03)
            let hasStrongIBAN = ibanScore >= 0.12
            let hasStrongAmount = amountScore >= 0.12
            let hasStrongKeywords = keywordScore >= 0.03

            let hasAnyStrongSignal = hasStrongIBAN || hasStrongAmount || hasStrongKeywords

            if !hasAnyStrongSignal {
                // Cap confidence below threshold
                let cappedScore = min(score, 0.65)
                if cappedScore < score {
                    // PRIVACY: Log only category and scores, not vendor name
                    logger.debug("STRONG SIGNAL GATE: category=\(candidate.documentCategoryRaw), strongIBAN=\(hasStrongIBAN), strongAmount=\(hasStrongAmount), strongKeywords=\(hasStrongKeywords)")
                    logger.debug("Capping confidence from \(String(format: "%.3f", score)) to \(String(format: "%.3f", cappedScore))")
                    score = cappedScore
                    strongSignalGateApplied = true
                }
            } else {
                logger.debug("Strong signal gate PASSED: category=\(candidate.documentCategoryRaw), IBAN=\(hasStrongIBAN), amount=\(hasStrongAmount), keywords=\(hasStrongKeywords)")
            }
        }

        // ---------------------------------------------------------------------
        // Log Comprehensive Score Breakdown (PRIVACY: no vendor name)
        // ---------------------------------------------------------------------
        logger.debug("=== SCORE BREAKDOWN ===")
        for item in scoreBreakdown {
            logger.debug("  \(item)")
        }
        if strongSignalGateApplied {
            logger.debug("  [CAPPED by strong signal gate]")
        }
        logger.info("Score: total=\(String(format: "%.3f", score)), threshold=\(Self.suggestionThreshold), decision=\(score >= Self.suggestionThreshold ? "SUGGEST" : "SKIP")")

        return min(max(score, 0.0), 1.0)
    }

    /// Scores due date consistency using bucketing approach (+/-3 days tolerance).
    /// This handles weekend/holiday shifts where vendor moves due date by a few days.
    ///
    /// Scoring:
    /// - 95%+ in bucket -> 0.35 (perfect)
    /// - 80%+ in bucket -> 0.30 (very good)
    /// - 60%+ in bucket -> 0.22 (good)
    /// - < 60% -> scaled 0.0-0.15
    private func scoreDueDateConsistency(candidate: RecurringCandidate, documents: [FinanceDocument]) -> Double {
        // Use pre-calculated stability ratio if available
        if let stabilityRatio = candidate.dueDateBucketStabilityRatio {
            return scoreDueDateFromStabilityRatio(stabilityRatio)
        }

        // Fallback to dominant day percentage if bucket ratio not calculated
        if let percentage = candidate.dominantDueDayPercentage {
            // Map percentage to score (less tolerant than bucket approach)
            if percentage >= 1.0 {
                return 0.35
            } else if percentage >= 0.9 {
                return 0.30
            } else if percentage >= 0.8 {
                return 0.25
            } else if percentage >= 0.7 {
                return 0.20
            } else if percentage >= 0.5 {
                return 0.12
            }
        }

        // No due date data
        return 0.0
    }

    /// Converts stability ratio to score.
    private func scoreDueDateFromStabilityRatio(_ stabilityRatio: Double) -> Double {
        // Weight: 0.35 (max)
        if stabilityRatio >= 0.95 {
            return 0.35  // Perfect - nearly all in bucket
        } else if stabilityRatio >= 0.80 {
            return 0.30  // Very good
        } else if stabilityRatio >= 0.60 {
            return 0.22  // Good
        } else if stabilityRatio >= 0.40 {
            return 0.12  // Moderate
        } else {
            return 0.0   // Poor - not a clear pattern
        }
    }

    private func findDominantDay(_ days: [Int]) -> (day: Int?, percentage: Double?) {
        guard !days.isEmpty else { return (nil, nil) }

        let dayCount = Dictionary(grouping: days, by: { $0 }).mapValues { $0.count }
        guard let dominant = dayCount.max(by: { $0.value < $1.value }) else {
            return (nil, nil)
        }

        let percentage = Double(dominant.value) / Double(days.count)
        return (dominant.key, percentage)
    }

    private func calculateStdDev(_ values: [Int]) -> Double? {
        guard values.count >= 2 else { return nil }

        let doubleValues = values.map(Double.init)
        let mean = doubleValues.reduce(0, +) / Double(doubleValues.count)
        let squaredDiffs = doubleValues.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(squaredDiffs.count)
        return sqrt(variance)
    }
}
