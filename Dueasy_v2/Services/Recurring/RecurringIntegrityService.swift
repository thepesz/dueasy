import Foundation
import SwiftData
import os.log

/// Service for maintaining data integrity in the recurring payment system.
/// Cleans up orphaned references and validates relationships.
///
/// CRITICAL FIX: This service addresses data integrity issues where:
/// - Instances can become orphaned when templates are deleted
/// - Documents can have stale references to deleted instances
/// - Candidates can reference deleted templates
///
/// Should be called on app launch to ensure data consistency.
@MainActor
final class RecurringIntegrityService {

    private let modelContext: ModelContext
    private let calendarService: CalendarServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringIntegrity")

    /// Result of integrity check operations
    struct IntegrityCheckResult {
        let orphanedInstancesRemoved: Int
        let orphanedDocumentReferencesCleared: Int
        let orphanedCandidatesRemoved: Int
        let amountPrecisionMigrations: Int

        var totalIssuesFixed: Int {
            orphanedInstancesRemoved + orphanedDocumentReferencesCleared + orphanedCandidatesRemoved + amountPrecisionMigrations
        }

        var hasIssues: Bool {
            totalIssuesFixed > 0
        }
    }

    init(
        modelContext: ModelContext,
        calendarService: CalendarServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.modelContext = modelContext
        self.calendarService = calendarService
        self.notificationService = notificationService
    }

    /// Runs all integrity checks and cleanups.
    /// Should be called on app launch or periodically.
    /// - Returns: Summary of issues found and fixed
    @discardableResult
    func runIntegrityChecks() async throws -> IntegrityCheckResult {
        logger.info("Starting recurring payment integrity checks...")

        let orphanedInstances = try await cleanupOrphanedInstances()
        let orphanedDocuments = try await cleanupOrphanedDocumentReferences()
        let orphanedCandidates = try await cleanupOrphanedCandidates()
        let amountMigrations = try await migrateAmountPrecision()

        let result = IntegrityCheckResult(
            orphanedInstancesRemoved: orphanedInstances,
            orphanedDocumentReferencesCleared: orphanedDocuments,
            orphanedCandidatesRemoved: orphanedCandidates,
            amountPrecisionMigrations: amountMigrations
        )

        if result.hasIssues {
            logger.warning("Integrity checks complete: removed \(orphanedInstances) orphaned instances, cleared \(orphanedDocuments) document references, removed \(orphanedCandidates) orphaned candidates, migrated \(amountMigrations) amount values")
        } else {
            logger.info("Integrity checks complete: no issues found")
        }

        return result
    }

    // MARK: - Orphaned Instance Cleanup

    /// Removes instances whose template no longer exists.
    /// Also handles cleanup of linked documents and calendar events.
    /// - Returns: Number of orphaned instances removed
    private func cleanupOrphanedInstances() async throws -> Int {
        // Fetch all templates to build valid ID set
        let templateDescriptor = FetchDescriptor<RecurringTemplate>()
        let templates = try modelContext.fetch(templateDescriptor)
        let validTemplateIds = Set(templates.map { $0.id })

        logger.debug("Found \(templates.count) valid templates")

        // Fetch all instances
        let instanceDescriptor = FetchDescriptor<RecurringInstance>()
        let instances = try modelContext.fetch(instanceDescriptor)

        var removedCount = 0

        for instance in instances {
            // Check if instance's template still exists
            if !validTemplateIds.contains(instance.templateId) {
                logger.warning("Found orphaned instance: \(instance.id) (template \(instance.templateId) not found)")

                // Clear any linked document's recurring references
                if let docId = instance.matchedDocumentId {
                    await clearDocumentRecurringLinkage(documentId: docId)
                }

                // Cancel notifications for this instance
                if instance.notificationsScheduled {
                    await notificationService.cancelNotifications(ids: instance.scheduledNotificationIds)
                    logger.debug("Cancelled notifications for orphaned instance")
                }

                // Delete calendar event if exists
                if let eventId = instance.calendarEventId {
                    do {
                        try await calendarService.deleteEvent(eventId: eventId)
                        logger.debug("Deleted calendar event for orphaned instance")
                    } catch {
                        logger.warning("Failed to delete calendar event for orphaned instance: \(error.localizedDescription)")
                    }
                }

                // Delete the orphaned instance
                modelContext.delete(instance)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            try modelContext.save()
            logger.info("Removed \(removedCount) orphaned instances")
        }

        return removedCount
    }

    // MARK: - Orphaned Document Reference Cleanup

    /// Clears recurring references from documents pointing to deleted instances.
    /// - Returns: Number of document references cleared
    private func cleanupOrphanedDocumentReferences() async throws -> Int {
        // Fetch all instances to build valid ID set
        let instanceDescriptor = FetchDescriptor<RecurringInstance>()
        let instances = try modelContext.fetch(instanceDescriptor)
        let validInstanceIds = Set(instances.map { $0.id })

        logger.debug("Found \(instances.count) valid instances")

        // Fetch all documents with recurring linkage
        let documentDescriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.recurringInstanceId != nil }
        )
        let documents = try modelContext.fetch(documentDescriptor)

        var cleanedCount = 0

        for document in documents {
            if let instanceId = document.recurringInstanceId,
               !validInstanceIds.contains(instanceId) {
                logger.warning("Found orphaned instance reference in document \(document.id) -> instance \(instanceId)")

                // Clear the orphaned reference
                document.recurringInstanceId = nil
                document.recurringTemplateId = nil
                document.markUpdated()

                cleanedCount += 1
            }
        }

        if cleanedCount > 0 {
            try modelContext.save()
            logger.info("Cleared \(cleanedCount) orphaned document references")
        }

        return cleanedCount
    }

    // MARK: - Orphaned Candidate Cleanup

    /// Removes candidates whose created template no longer exists.
    /// - Returns: Number of orphaned candidates removed
    private func cleanupOrphanedCandidates() async throws -> Int {
        // Fetch all templates to build valid ID set
        let templateDescriptor = FetchDescriptor<RecurringTemplate>()
        let templates = try modelContext.fetch(templateDescriptor)
        let validTemplateIds = Set(templates.map { $0.id })

        // Fetch all candidates with a created template reference
        let candidateDescriptor = FetchDescriptor<RecurringCandidate>(
            predicate: #Predicate<RecurringCandidate> { $0.createdTemplateId != nil }
        )
        let candidates = try modelContext.fetch(candidateDescriptor)

        var removedCount = 0

        for candidate in candidates {
            if let templateId = candidate.createdTemplateId,
               !validTemplateIds.contains(templateId) {
                logger.warning("Found orphaned candidate: \(candidate.id) (template \(templateId) not found)")

                // Delete the orphaned candidate
                modelContext.delete(candidate)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            try modelContext.save()
            logger.info("Removed \(removedCount) orphaned candidates")
        }

        return removedCount
    }

    // MARK: - Amount Precision Migration

    /// Migrates template amount storage from Double to String for precision.
    /// This is a one-time migration that runs on app launch.
    /// - Returns: Number of templates migrated
    private func migrateAmountPrecision() async throws -> Int {
        let templateDescriptor = FetchDescriptor<RecurringTemplate>()
        let templates = try modelContext.fetch(templateDescriptor)

        var migratedCount = 0

        for template in templates {
            var needsMigration = false

            // Check if using legacy Double storage (amountMinValue/amountMaxValue)
            // by accessing the computed properties which will trigger migration on write
            if let minAmount = template.amountMin {
                // Re-setting the value triggers the setter which uses String storage
                template.amountMin = minAmount
                needsMigration = true
            }

            if let maxAmount = template.amountMax {
                template.amountMax = maxAmount
                needsMigration = true
            }

            if needsMigration {
                template.markUpdated()
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            try modelContext.save()
            logger.info("Migrated \(migratedCount) templates to String amount storage")
        }

        return migratedCount
    }

    // MARK: - Helper Methods

    /// Clears recurring linkage from a specific document.
    private func clearDocumentRecurringLinkage(documentId: UUID) async {
        let predicate = #Predicate<FinanceDocument> { $0.id == documentId }
        let descriptor = FetchDescriptor<FinanceDocument>(predicate: predicate)

        do {
            if let document = try modelContext.fetch(descriptor).first {
                document.recurringInstanceId = nil
                document.recurringTemplateId = nil
                document.markUpdated()
                logger.debug("Cleared recurring linkage from document \(documentId)")
            } else {
                logger.debug("Document \(documentId) not found - may have been deleted")
            }
        } catch {
            logger.error("Failed to clear document linkage: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation Methods

    /// Validates that all recurring relationships are consistent.
    /// Returns issues found without modifying data.
    /// - Returns: Array of validation issue descriptions
    func validateIntegrity() async throws -> [String] {
        var issues: [String] = []

        // Check for orphaned instances
        let templateDescriptor = FetchDescriptor<RecurringTemplate>()
        let templates = try modelContext.fetch(templateDescriptor)
        let validTemplateIds = Set(templates.map { $0.id })

        let instanceDescriptor = FetchDescriptor<RecurringInstance>()
        let instances = try modelContext.fetch(instanceDescriptor)

        for instance in instances {
            if !validTemplateIds.contains(instance.templateId) {
                issues.append("Instance \(instance.id) references non-existent template \(instance.templateId)")
            }
        }

        // Check for orphaned document references
        let validInstanceIds = Set(instances.map { $0.id })

        let documentDescriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.recurringInstanceId != nil }
        )
        let documents = try modelContext.fetch(documentDescriptor)

        for document in documents {
            if let instanceId = document.recurringInstanceId,
               !validInstanceIds.contains(instanceId) {
                issues.append("Document \(document.id) references non-existent instance \(instanceId)")
            }
        }

        // Check for orphaned candidates
        let candidateDescriptor = FetchDescriptor<RecurringCandidate>(
            predicate: #Predicate<RecurringCandidate> { $0.createdTemplateId != nil }
        )
        let candidates = try modelContext.fetch(candidateDescriptor)

        for candidate in candidates {
            if let templateId = candidate.createdTemplateId,
               !validTemplateIds.contains(templateId) {
                issues.append("Candidate \(candidate.id) references non-existent template \(templateId)")
            }
        }

        return issues
    }

    // MARK: - Vendor Fingerprint Change Detection

    /// Result of vendor fingerprint analysis
    struct VendorFingerprintAnalysis {
        /// Groups of documents that might be from the same vendor but have different fingerprints
        let potentialMerges: [PotentialVendorMerge]

        /// True if there are potential merges that need attention
        var hasIssues: Bool { !potentialMerges.isEmpty }
    }

    /// Represents a potential vendor merge scenario
    struct PotentialVendorMerge {
        let normalizedVendorName: String
        let fingerprints: [String]
        let documentCounts: [String: Int]  // fingerprint -> count
        let suggestedAction: String
    }

    /// Detects if vendors have fingerprints that changed over time.
    /// This handles cases where:
    /// - Vendor updates their NIP
    /// - Vendor name formatting changes slightly
    /// - Old invoices and new invoices are treated as separate patterns
    ///
    /// This is a diagnostic tool for Iteration 1 - manual review recommended.
    /// Iteration 2 will implement auto-detection and merge suggestions.
    ///
    /// - Returns: Analysis of potential vendor fingerprint issues
    func detectVendorFingerprintChanges() async throws -> VendorFingerprintAnalysis {
        logger.info("Starting vendor fingerprint change detection...")

        // Fetch all documents with fingerprints
        let documentDescriptor = FetchDescriptor<FinanceDocument>()
        let allDocuments = try modelContext.fetch(documentDescriptor)

        // Group documents by normalized vendor name (lowercased, whitespace normalized)
        var vendorGroups: [String: [FinanceDocument]] = [:]

        for document in allDocuments {
            let normalizedName = normalizeVendorName(document.title)
            if vendorGroups[normalizedName] == nil {
                vendorGroups[normalizedName] = []
            }
            vendorGroups[normalizedName]?.append(document)
        }

        // Find groups with multiple different fingerprints
        var potentialMerges: [PotentialVendorMerge] = []

        for (normalizedName, documents) in vendorGroups {
            // Collect unique fingerprints for this vendor group
            var fingerprintCounts: [String: Int] = [:]
            for doc in documents {
                if let fingerprint = doc.vendorFingerprint {
                    fingerprintCounts[fingerprint, default: 0] += 1
                }
            }

            // If there are multiple fingerprints, it's a potential merge candidate
            if fingerprintCounts.count > 1 {
                // Check if any fingerprints are already linked to templates
                var templateLinkedFingerprints: Set<String> = []
                let templateDescriptor = FetchDescriptor<RecurringTemplate>()
                let templates = try modelContext.fetch(templateDescriptor)

                for template in templates {
                    templateLinkedFingerprints.insert(template.vendorFingerprint)
                }

                let hasMultipleTemplates = fingerprintCounts.keys.filter { templateLinkedFingerprints.contains($0) }.count > 1

                let suggestedAction: String
                if hasMultipleTemplates {
                    suggestedAction = "Multiple recurring templates exist for this vendor. Consider merging templates manually."
                } else if fingerprintCounts.keys.contains(where: { templateLinkedFingerprints.contains($0) }) {
                    suggestedAction = "Some documents may belong to an existing recurring template. Review and link if appropriate."
                } else {
                    suggestedAction = "Multiple fingerprints detected. This may indicate vendor info changes over time."
                }

                let merge = PotentialVendorMerge(
                    normalizedVendorName: normalizedName,
                    fingerprints: Array(fingerprintCounts.keys),
                    documentCounts: fingerprintCounts,
                    suggestedAction: suggestedAction
                )
                potentialMerges.append(merge)

                logger.debug("Potential merge: '\(normalizedName)' has \(fingerprintCounts.count) fingerprints")
            }
        }

        if potentialMerges.isEmpty {
            logger.info("No vendor fingerprint issues detected")
        } else {
            logger.warning("Detected \(potentialMerges.count) vendors with potential fingerprint changes")
        }

        return VendorFingerprintAnalysis(potentialMerges: potentialMerges)
    }

    /// Normalizes a vendor name for comparison purposes.
    /// - Lowercases
    /// - Removes extra whitespace
    /// - Removes common suffixes (Sp. z o.o., S.A., etc.)
    private func normalizeVendorName(_ name: String) -> String {
        var normalized = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common Polish company suffixes for comparison
        let suffixes = [
            "sp. z o.o.",
            "sp.z.o.o.",
            "sp z o.o.",
            "spzoo",
            "sp. z o.o",
            "s.a.",
            "sa",
            "sp. j.",
            "sp. k.",
            "s.k.a."
        ]

        for suffix in suffixes {
            if normalized.hasSuffix(suffix) {
                normalized = String(normalized.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Normalize whitespace
        normalized = normalized.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return normalized
    }
}
