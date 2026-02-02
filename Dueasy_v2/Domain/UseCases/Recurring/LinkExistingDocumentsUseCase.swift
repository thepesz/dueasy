import Foundation
import os.log

/// Use case for linking existing documents to a newly created recurring template.
/// This is called after accepting a recurring suggestion to connect the documents
/// that were used for detection to their corresponding instances.
///
/// Flow:
/// 1. Find all documents matching the template's vendor fingerprint
/// 2. For each document, find the matching instance (by due date)
/// 3. Link document to instance and update instance status
/// 4. CRITICAL: Save changes to persist the linkage
final class LinkExistingDocumentsUseCase: @unchecked Sendable {

    private let documentRepository: DocumentRepositoryProtocol
    private let schedulerService: RecurringSchedulerServiceProtocol
    private let dateService: RecurringDateServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "LinkExistingDocuments")

    init(
        documentRepository: DocumentRepositoryProtocol,
        schedulerService: RecurringSchedulerServiceProtocol,
        dateService: RecurringDateServiceProtocol = RecurringDateService()
    ) {
        self.documentRepository = documentRepository
        self.schedulerService = schedulerService
        self.dateService = dateService
    }

    /// Links existing documents to a recurring template's instances.
    /// - Parameters:
    ///   - template: The recurring template to link documents to
    ///   - toleranceDays: Days tolerance for matching due dates (default: 3)
    /// - Returns: Number of documents successfully linked
    @MainActor
    func execute(template: RecurringTemplate, toleranceDays: Int = 3) async throws -> Int {
        logger.debug("Linking documents for template: \(template.id), toleranceDays: \(toleranceDays)")
        logger.debug("Fingerprint prefix: \(PrivacyLogger.sanitizeFingerprint(template.vendorFingerprint))")

        // Find all documents matching the vendor fingerprint
        let matchingDocuments = try await documentRepository.fetch(
            byVendorFingerprint: template.vendorFingerprint
        )
        logger.info("Found \(matchingDocuments.count) documents matching fingerprint")

        // DIAGNOSTIC: If no documents found, log counts only (no PII)
        if matchingDocuments.isEmpty {
            logger.error("NO DOCUMENTS FOUND! Checking document count...")
            let allDocs = try await documentRepository.fetchAll()
            logger.error("Total documents in database: \(allDocs.count)")
            let withFingerprint = allDocs.filter { $0.vendorFingerprint != nil }.count
            logger.error("Documents with fingerprint: \(withFingerprint)")
        }

        // PRIVACY: Log count only, not titles or dates
        logger.info("Found \(matchingDocuments.count) documents to process")

        // Fetch all instances for this template
        let instances = try await schedulerService.fetchInstances(forTemplateId: template.id)
        logger.info("Found \(instances.count) instances for template")

        var linkedCount = 0
        var skippedAlreadyLinked = 0
        var skippedNoDueDate = 0
        var linkedDocuments: [FinanceDocument] = []

        for document in matchingDocuments {
            // Skip documents already linked to recurring
            if document.recurringInstanceId != nil || document.recurringTemplateId != nil {
                skippedAlreadyLinked += 1
                continue
            }

            // Skip documents without a due date
            guard let documentDueDate = document.dueDate else {
                skippedNoDueDate += 1
                continue
            }

            // Find matching instance by due date (within tolerance)
            var matchingInstance = findMatchingInstance(
                for: documentDueDate,
                in: instances,
                toleranceDays: toleranceDays
            )

            // CRITICAL FIX: If no matching instance exists (e.g., document is from a past month),
            // create a historical instance for it.
            // This handles the case where template was just created but documents are from past months.
            if matchingInstance == nil {
                // Get the period key for this document's due date
                let periodKey = dateService.periodKey(for: documentDueDate)

                // Check if an instance already exists for this period (might have been skipped in tolerance check)
                let existingForPeriod = instances.first { $0.periodKey == periodKey }
                if let existing = existingForPeriod {
                    matchingInstance = existing
                } else {
                    // Create a historical instance using the scheduler service
                    do {
                        let historicalInstance = try await schedulerService.createHistoricalInstance(
                            for: template,
                            periodKey: periodKey,
                            expectedDueDate: documentDueDate
                        )
                        matchingInstance = historicalInstance
                    } catch {
                        logger.error("Failed to create historical instance: \(error.localizedDescription)")
                        // Still link the document to the template even without an instance
                        document.recurringTemplateId = template.id
                        document.markUpdated()
                        linkedDocuments.append(document)
                        linkedCount += 1
                        continue
                    }
                }
            }

            guard let matchingInstance = matchingInstance else {
                continue
            }

            // Link document to instance
            document.recurringInstanceId = matchingInstance.id
            document.recurringTemplateId = template.id
            document.markUpdated()

            // Match the document to the instance
            matchingInstance.matchDocument(
                documentId: document.id,
                dueDate: documentDueDate,
                amount: document.amount,
                invoiceNumber: document.documentNumber
            )

            // If document is already paid, mark instance as paid
            if document.status == .paid {
                matchingInstance.markAsPaid()
            }

            linkedDocuments.append(document)
            linkedCount += 1
        }

        // Log summary of skipped documents
        if skippedAlreadyLinked > 0 || skippedNoDueDate > 0 {
            logger.debug("Skipped: alreadyLinked=\(skippedAlreadyLinked), noDueDate=\(skippedNoDueDate)")
        }

        // CRITICAL: Save all changes to persist the linkage
        if linkedCount > 0 {
            do {
                try await documentRepository.save()
                logger.info("Linked and saved \(linkedCount) documents to template")
            } catch {
                logger.error("Save failed: \(error.localizedDescription)")
                throw error
            }
        }

        logger.info("Link complete: \(linkedCount) documents linked")
        return linkedCount
    }

    // MARK: - Helpers

    /// Finds an instance that matches the given due date within tolerance.
    private func findMatchingInstance(
        for dueDate: Date,
        in instances: [RecurringInstance],
        toleranceDays: Int
    ) -> RecurringInstance? {
        let tolerance = TimeInterval(toleranceDays * 24 * 60 * 60)

        return instances.first { instance in
            let timeDifference = abs(instance.effectiveDueDate.timeIntervalSince(dueDate))
            return timeDifference <= tolerance
        }
    }
}
