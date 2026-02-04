import Foundation
import SwiftData
import os.log

/// Result of fingerprint migration analysis for a single template.
struct TemplateMigrationAnalysis: Sendable {
    /// The template being analyzed
    let templateId: UUID
    let vendorDisplayName: String

    /// Current fingerprint (legacy, without amount bucket)
    let currentFingerprint: String

    /// Documents linked to this template
    let linkedDocumentCount: Int

    /// Distinct amount buckets found in linked documents
    let distinctAmountBuckets: [String]

    /// Whether this template needs splitting (has multiple distinct amount buckets)
    var needsSplit: Bool {
        distinctAmountBuckets.count > 1
    }

    /// Suggested new templates to create (one per amount bucket)
    let suggestedSplits: [SuggestedTemplateSplit]
}

/// Suggested split for a template with multiple amount buckets.
struct SuggestedTemplateSplit: Sendable {
    /// Amount bucket identifier
    let amountBucket: String

    /// Documents that belong to this bucket
    let documentIds: [UUID]

    /// Average amount in this bucket
    let averageAmount: Decimal

    /// Suggested display name suffix (e.g., "Santander - Credit Card" vs "Santander - Loan")
    let suggestedSuffix: String?
}

/// Service for migrating existing templates to use amount-bucketed fingerprints.
///
/// **Background:**
/// Version 1 fingerprints only used vendor name + NIP, which caused issues when
/// a single vendor has multiple recurring payments at different amounts (e.g.,
/// "Santander Credit Card" at 500 PLN and "Santander Loan" at 1200 PLN).
///
/// Version 2 fingerprints include amount buckets to separate these cases.
///
/// **Migration Strategy:**
/// 1. Analyze all existing templates
/// 2. For each template, examine linked documents
/// 3. If documents have significantly different amounts (>50%), suggest splitting
/// 4. User can accept/reject splits through UI, or auto-migrate if patterns are clear
///
/// **Backward Compatibility:**
/// - Existing templates continue to work until migrated
/// - Migration is opt-in (user-triggered) or automatic when patterns are unambiguous
///
/// **Thread Safety:** All methods require `@MainActor` due to SwiftData constraints.
protocol FingerprintMigrationServiceProtocol: Sendable {
    /// Analyzes all templates and identifies those that need migration.
    ///
    /// Examines each template's linked documents and groups them by amount bucket.
    /// Templates with documents in multiple distinct buckets may need splitting.
    ///
    /// - Returns: Array of `TemplateMigrationAnalysis` for each template.
    /// - Throws: SwiftData fetch errors.
    func analyzeAllTemplates() async throws -> [TemplateMigrationAnalysis]

    /// Analyzes a single template for potential splits.
    ///
    /// Groups the template's linked documents by amount bucket and determines
    /// if the template should be split into multiple templates.
    ///
    /// - Parameter template: The template to analyze.
    /// - Returns: A `TemplateMigrationAnalysis` with split suggestions.
    /// - Throws: SwiftData fetch errors.
    func analyzeTemplate(_ template: RecurringTemplate) async throws -> TemplateMigrationAnalysis

    /// Performs automatic migration for templates with clear splits.
    ///
    /// Only migrates if all of the following conditions are met:
    /// - Template has documents in multiple distinct amount buckets
    /// - Each bucket has at least 2 documents (clear pattern)
    /// - Amount difference between buckets is >50%
    ///
    /// - Returns: Number of templates that were successfully migrated/split.
    /// - Throws: SwiftData errors during migration.
    func performAutomaticMigration() async throws -> Int

    /// Splits a template according to the analysis results.
    ///
    /// Creates new templates for each amount bucket (except the one designated
    /// to keep the original) and reassigns documents to the appropriate templates.
    ///
    /// - Parameters:
    ///   - analysis: The migration analysis containing split suggestions.
    ///   - keepOriginalForBucket: Which amount bucket should retain the original
    ///     template ID. If `nil`, the first bucket is used.
    /// - Returns: Array of templates (original updated + newly created).
    /// - Throws: `RecurringError.templateNotFound` if the original template doesn't exist.
    /// - Throws: SwiftData errors during split operation.
    func splitTemplate(
        analysis: TemplateMigrationAnalysis,
        keepOriginalForBucket: String?
    ) async throws -> [RecurringTemplate]

    /// Backfills vendor-only fingerprints for templates that don't have them.
    ///
    /// This is needed for templates created before vendor-only fingerprints were
    /// introduced. The vendor-only fingerprint enables fuzzy matching.
    ///
    /// - Returns: Number of templates that were updated.
    /// - Throws: SwiftData errors.
    func backfillVendorOnlyFingerprints() async throws -> Int
}

/// Default implementation of FingerprintMigrationService.
///
/// Note: `@MainActor` is required because SwiftData's `ModelContext` is not Sendable
/// and must be accessed from the main actor. This constraint is inherent to SwiftData's
/// design and cannot be avoided while using ModelContext directly.
@MainActor
final class FingerprintMigrationService: FingerprintMigrationServiceProtocol {

    private let modelContext: ModelContext
    private let fingerprintService: VendorFingerprintServiceProtocol
    private let templateService: RecurringTemplateServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "FingerprintMigration")

    init(
        modelContext: ModelContext,
        fingerprintService: VendorFingerprintServiceProtocol,
        templateService: RecurringTemplateServiceProtocol
    ) {
        self.modelContext = modelContext
        self.fingerprintService = fingerprintService
        self.templateService = templateService
    }

    // MARK: - Analysis

    func analyzeAllTemplates() async throws -> [TemplateMigrationAnalysis] {
        logger.info("Starting migration analysis for all templates")

        let descriptor = FetchDescriptor<RecurringTemplate>()
        let templates = try modelContext.fetch(descriptor)

        var analyses: [TemplateMigrationAnalysis] = []

        for template in templates {
            let analysis = try await analyzeTemplate(template)
            analyses.append(analysis)
        }

        let needsSplitCount = analyses.filter { $0.needsSplit }.count
        logger.info("Migration analysis complete: \(templates.count) templates analyzed, \(needsSplitCount) need splitting")

        return analyses
    }

    func analyzeTemplate(_ template: RecurringTemplate) async throws -> TemplateMigrationAnalysis {
        // Fetch all documents linked to this template
        let templateId = template.id
        let descriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.recurringTemplateId == templateId }
        )
        let documents = try modelContext.fetch(descriptor)

        // Group documents by amount bucket
        var bucketGroups: [String: [FinanceDocument]] = [:]
        for document in documents {
            let bucket = fingerprintService.calculateAmountBucket(document.amount)
            bucketGroups[bucket, default: []].append(document)
        }

        // Create suggested splits
        var suggestedSplits: [SuggestedTemplateSplit] = []
        for (bucket, docs) in bucketGroups.sorted(by: { $0.key < $1.key }) {
            let totalAmount = docs.reduce(Decimal(0)) { $0 + $1.amount }
            let averageAmount = totalAmount / Decimal(docs.count)

            // Try to infer a suffix based on amount range
            let suffix = inferServiceSuffix(averageAmount: averageAmount, template: template)

            suggestedSplits.append(SuggestedTemplateSplit(
                amountBucket: bucket,
                documentIds: docs.map { $0.id },
                averageAmount: averageAmount,
                suggestedSuffix: suffix
            ))
        }

        return TemplateMigrationAnalysis(
            templateId: template.id,
            vendorDisplayName: template.vendorDisplayName,
            currentFingerprint: template.vendorFingerprint,
            linkedDocumentCount: documents.count,
            distinctAmountBuckets: Array(bucketGroups.keys).sorted(),
            suggestedSplits: suggestedSplits
        )
    }

    // MARK: - Migration

    func performAutomaticMigration() async throws -> Int {
        logger.info("Starting automatic fingerprint migration")

        let analyses = try await analyzeAllTemplates()
        var migratedCount = 0

        for analysis in analyses {
            // Only auto-migrate if:
            // 1. Template needs splitting (multiple buckets)
            // 2. Each bucket has at least 2 documents (clear pattern)
            // 3. Bucket amounts are sufficiently different (>50% difference)
            guard analysis.needsSplit else { continue }

            let allBucketsHavePattern = analysis.suggestedSplits.allSatisfy { $0.documentIds.count >= 2 }
            guard allBucketsHavePattern else {
                logger.debug("Skipping auto-migration for template \(analysis.templateId): not all buckets have clear pattern")
                continue
            }

            // Check amount difference between buckets
            let amounts = analysis.suggestedSplits.map { $0.averageAmount }
            guard amounts.count >= 2 else { continue }

            let minAmount = amounts.min()!
            let maxAmount = amounts.max()!
            let difference = (maxAmount - minAmount) / minAmount
            let differencePercent = NSDecimalNumber(decimal: difference).doubleValue * 100

            if differencePercent < 50 {
                logger.debug("Skipping auto-migration for template \(analysis.templateId): amount difference too small (\(String(format: "%.1f", differencePercent))%)")
                continue
            }

            // Perform the split
            logger.info("Auto-migrating template \(analysis.templateId): \(analysis.distinctAmountBuckets.count) buckets, \(String(format: "%.1f", differencePercent))% amount difference")
            _ = try await splitTemplate(analysis: analysis, keepOriginalForBucket: analysis.suggestedSplits.first?.amountBucket)
            migratedCount += 1
        }

        logger.info("Automatic migration complete: \(migratedCount) templates split")
        return migratedCount
    }

    func splitTemplate(
        analysis: TemplateMigrationAnalysis,
        keepOriginalForBucket: String?
    ) async throws -> [RecurringTemplate] {
        guard analysis.needsSplit else {
            logger.debug("Template \(analysis.templateId) does not need splitting")
            guard let template = try await templateService.fetchTemplate(byId: analysis.templateId) else {
                throw RecurringError.templateNotFound
            }
            return [template]
        }

        guard let originalTemplate = try await templateService.fetchTemplate(byId: analysis.templateId) else {
            throw RecurringError.templateNotFound
        }

        var resultTemplates: [RecurringTemplate] = []
        let bucketToKeep = keepOriginalForBucket ?? analysis.suggestedSplits.first?.amountBucket

        for split in analysis.suggestedSplits {
            if split.amountBucket == bucketToKeep {
                // Update original template with new fingerprint
                let newFingerprint = fingerprintService.generateFingerprint(
                    vendorName: originalTemplate.vendorDisplayName,
                    nip: nil,
                    amount: split.averageAmount
                )
                let vendorOnlyFingerprint = fingerprintService.generateVendorOnlyFingerprint(
                    vendorName: originalTemplate.vendorDisplayName,
                    nip: nil
                )

                originalTemplate.vendorFingerprint = newFingerprint
                originalTemplate.vendorOnlyFingerprint = vendorOnlyFingerprint
                originalTemplate.amountBucket = split.amountBucket
                originalTemplate.amountMin = split.averageAmount * Decimal(0.85)
                originalTemplate.amountMax = split.averageAmount * Decimal(1.15)
                originalTemplate.markUpdated()

                // Update linked documents
                try await updateDocumentFingerprints(documentIds: split.documentIds, newFingerprint: newFingerprint)

                resultTemplates.append(originalTemplate)
                logger.info("Updated original template \(originalTemplate.id) with bucket \(split.amountBucket)")
            } else {
                // Create new template for this bucket
                let newFingerprint = fingerprintService.generateFingerprint(
                    vendorName: originalTemplate.vendorDisplayName,
                    nip: nil,
                    amount: split.averageAmount
                )
                let vendorOnlyFingerprint = fingerprintService.generateVendorOnlyFingerprint(
                    vendorName: originalTemplate.vendorDisplayName,
                    nip: nil
                )

                // Create display name with suffix if available
                let displayName: String
                if let suffix = split.suggestedSuffix {
                    displayName = "\(originalTemplate.vendorDisplayName) - \(suffix)"
                } else {
                    displayName = "\(originalTemplate.vendorDisplayName) (\(split.amountBucket.replacingOccurrences(of: "bucket_", with: "~")))"
                }

                let newTemplate = RecurringTemplate(
                    vendorFingerprint: newFingerprint,
                    vendorOnlyFingerprint: vendorOnlyFingerprint,
                    amountBucket: split.amountBucket,
                    vendorDisplayName: displayName,
                    vendorShortName: originalTemplate.vendorShortName,
                    documentCategory: originalTemplate.documentCategory,
                    dueDayOfMonth: originalTemplate.dueDayOfMonth,
                    toleranceDays: originalTemplate.toleranceDays,
                    reminderOffsetsDays: originalTemplate.reminderOffsetsDays,
                    amountMin: split.averageAmount * Decimal(0.85),
                    amountMax: split.averageAmount * Decimal(1.15),
                    currency: originalTemplate.currency,
                    iban: originalTemplate.iban,
                    isActive: originalTemplate.isActive,
                    creationSource: .manual
                )

                modelContext.insert(newTemplate)

                // Update linked documents to point to new template
                try await updateDocumentFingerprints(
                    documentIds: split.documentIds,
                    newFingerprint: newFingerprint,
                    newTemplateId: newTemplate.id
                )

                resultTemplates.append(newTemplate)
                logger.info("Created new template \(newTemplate.id) for bucket \(split.amountBucket)")
            }
        }

        try modelContext.save()
        return resultTemplates
    }

    func backfillVendorOnlyFingerprints() async throws -> Int {
        logger.info("Backfilling vendor-only fingerprints for existing templates")

        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.vendorOnlyFingerprint == nil }
        )
        let templates = try modelContext.fetch(descriptor)

        var updatedCount = 0
        for template in templates {
            let vendorOnlyFingerprint = fingerprintService.generateVendorOnlyFingerprint(
                vendorName: template.vendorDisplayName,
                nip: nil
            )
            template.vendorOnlyFingerprint = vendorOnlyFingerprint
            template.markUpdated()
            updatedCount += 1
        }

        if updatedCount > 0 {
            try modelContext.save()
        }

        logger.info("Backfilled \(updatedCount) templates with vendor-only fingerprints")
        return updatedCount
    }

    // MARK: - Private Helpers

    private func updateDocumentFingerprints(
        documentIds: [UUID],
        newFingerprint: String,
        newTemplateId: UUID? = nil
    ) async throws {
        for documentId in documentIds {
            let descriptor = FetchDescriptor<FinanceDocument>(
                predicate: #Predicate<FinanceDocument> { $0.id == documentId }
            )
            guard let document = try modelContext.fetch(descriptor).first else { continue }

            document.vendorFingerprint = newFingerprint
            if let newTemplateId = newTemplateId {
                document.recurringTemplateId = newTemplateId
            }
            document.markUpdated()
        }
    }

    private func inferServiceSuffix(averageAmount: Decimal, template: RecurringTemplate) -> String? {
        // Try to infer a meaningful suffix based on amount patterns
        // This is heuristic and can be expanded based on real-world data

        let amountDouble = NSDecimalNumber(decimal: averageAmount).doubleValue

        // Common Polish financial product amounts
        switch amountDouble {
        case 0..<100:
            return "Subscription"
        case 100..<500:
            return "Service"
        case 500..<2000:
            return "Payment"
        case 2000..<10000:
            return "Installment"
        default:
            return nil
        }
    }
}
