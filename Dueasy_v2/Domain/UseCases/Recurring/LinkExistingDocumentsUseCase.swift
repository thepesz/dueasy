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
    private let logger = Logger(subsystem: "com.dueasy.app", category: "LinkExistingDocuments")

    init(
        documentRepository: DocumentRepositoryProtocol,
        schedulerService: RecurringSchedulerServiceProtocol
    ) {
        self.documentRepository = documentRepository
        self.schedulerService = schedulerService
    }

    /// Links existing documents to a recurring template's instances.
    /// - Parameters:
    ///   - template: The recurring template to link documents to
    ///   - toleranceDays: Days tolerance for matching due dates (default: 3)
    /// - Returns: Number of documents successfully linked
    @MainActor
    func execute(template: RecurringTemplate, toleranceDays: Int = 3) async throws -> Int {
        logger.info("=== LINK EXISTING DOCUMENTS USE CASE ===")
        logger.info("Template: \(template.vendorDisplayName) (ID: \(template.id))")
        logger.info("Vendor Fingerprint: \(template.vendorFingerprint)")
        logger.info("Tolerance Days: \(toleranceDays)")

        // DIAGNOSTIC: Log the fingerprint we're searching for
        let searchFingerprint = template.vendorFingerprint
        logger.info("SEARCHING for fingerprint: '\(searchFingerprint)'")
        logger.info("Fingerprint length: \(searchFingerprint.count)")
        logger.info("Fingerprint first 32 chars: '\(String(searchFingerprint.prefix(32)))'")

        // Find all documents matching the vendor fingerprint
        let matchingDocuments = try await documentRepository.fetch(
            byVendorFingerprint: template.vendorFingerprint
        )
        logger.info("Found \(matchingDocuments.count) documents for vendor fingerprint")

        // DIAGNOSTIC: If no documents found, log all documents to see what's there
        if matchingDocuments.isEmpty {
            logger.error("NO DOCUMENTS FOUND! Fetching ALL documents to diagnose...")
            let allDocs = try await documentRepository.fetchAll()
            logger.error("Total documents in database: \(allDocs.count)")
            for doc in allDocs {
                let docFP = doc.vendorFingerprint ?? "nil"
                let fpMatch = docFP == searchFingerprint
                logger.error("  Doc: '\(doc.title)' fp='\(docFP.prefix(32))...' match=\(fpMatch)")
            }
        }

        // Log each document found
        for (index, doc) in matchingDocuments.enumerated() {
            logger.info("  Document[\(index)]: id=\(doc.id), title=\(doc.title), dueDate=\(doc.dueDate?.description ?? "nil"), recurringInstanceId=\(doc.recurringInstanceId?.uuidString ?? "nil")")
        }

        // Fetch all instances for this template
        let instances = try await schedulerService.fetchInstances(forTemplateId: template.id)
        logger.info("Found \(instances.count) instances for template")

        // Log each instance
        for (index, instance) in instances.enumerated() {
            logger.info("  Instance[\(index)]: id=\(instance.id), period=\(instance.periodKey), expectedDue=\(instance.expectedDueDate), status=\(instance.status.rawValue)")
        }

        var linkedCount = 0
        var linkedDocuments: [FinanceDocument] = []

        for document in matchingDocuments {
            // Skip documents already linked to recurring
            if document.recurringInstanceId != nil || document.recurringTemplateId != nil {
                logger.info("SKIP: Document \(document.id) already linked (instanceId=\(document.recurringInstanceId?.uuidString ?? "nil"), templateId=\(document.recurringTemplateId?.uuidString ?? "nil"))")
                continue
            }

            // Skip documents without a due date
            guard let documentDueDate = document.dueDate else {
                logger.info("SKIP: Document \(document.id) has no due date")
                continue
            }

            logger.info("PROCESSING: Document \(document.id) with due date \(documentDueDate)")

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
                logger.info("NO EXISTING INSTANCE: Creating historical instance for this document's period...")

                // Get the period key for this document's due date
                let periodKey = RecurringInstance.periodKey(for: documentDueDate)
                logger.info("Document period key: \(periodKey)")

                // Check if an instance already exists for this period (might have been skipped in tolerance check)
                let existingForPeriod = instances.first { $0.periodKey == periodKey }
                if let existing = existingForPeriod {
                    logger.info("Instance exists for period \(periodKey) but due date didn't match within tolerance - using it anyway")
                    matchingInstance = existing
                } else {
                    // Create a historical instance using the scheduler service
                    logger.info("No instance exists for period \(periodKey) - creating historical instance via scheduler")
                    do {
                        let historicalInstance = try await schedulerService.createHistoricalInstance(
                            for: template,
                            periodKey: periodKey,
                            expectedDueDate: documentDueDate
                        )
                        logger.info("Created historical instance: \(historicalInstance.id) for period \(periodKey)")
                        matchingInstance = historicalInstance
                    } catch {
                        logger.error("Failed to create historical instance: \(error.localizedDescription)")
                        // Still link the document to the template even without an instance
                        document.recurringTemplateId = template.id
                        document.markUpdated()
                        linkedDocuments.append(document)
                        linkedCount += 1
                        logger.info("LINKED TO TEMPLATE ONLY (no instance): Document \(document.id) -> Template \(template.id)")
                        continue
                    }
                }
            }

            guard let matchingInstance = matchingInstance else {
                logger.info("NO MATCH: Could not find or create instance for document \(document.id) with due date \(documentDueDate)")
                continue
            }

            logger.info("MATCH FOUND: Instance \(matchingInstance.id) (expected: \(matchingInstance.expectedDueDate))")

            // Link document to instance
            document.recurringInstanceId = matchingInstance.id
            document.recurringTemplateId = template.id
            document.markUpdated()

            logger.info("SET document.recurringInstanceId = \(matchingInstance.id)")
            logger.info("SET document.recurringTemplateId = \(template.id)")

            // Match the document to the instance
            matchingInstance.matchDocument(
                documentId: document.id,
                dueDate: documentDueDate,
                amount: document.amount,
                invoiceNumber: document.documentNumber
            )

            logger.info("Instance \(matchingInstance.id) status after matchDocument: \(matchingInstance.status.rawValue)")

            // If document is already paid, mark instance as paid
            if document.status == .paid {
                matchingInstance.markAsPaid()
                logger.info("Document was paid, marked instance as paid: \(matchingInstance.status.rawValue)")
            }

            linkedDocuments.append(document)
            linkedCount += 1
            logger.info("LINKED: Document \(document.id) -> Instance \(matchingInstance.id) (total linked: \(linkedCount))")
        }

        // CRITICAL: Save all changes to persist the linkage
        if linkedCount > 0 {
            logger.info("SAVING: Persisting \(linkedCount) linked documents to database...")
            do {
                try await documentRepository.save()
                logger.info("SAVE SUCCESS: All document linkages persisted")

                // Verify the save worked by logging the document state
                // NOTE: SwiftData caches objects, so subsequent fetches by ViewModels
                // should use fetchFresh() to get the latest data from the database.
                for doc in linkedDocuments {
                    logger.info("VERIFY: Document \(doc.id) - recurringInstanceId=\(doc.recurringInstanceId?.uuidString ?? "nil"), recurringTemplateId=\(doc.recurringTemplateId?.uuidString ?? "nil")")
                }
            } catch {
                logger.error("SAVE FAILED: \(error.localizedDescription)")
                throw error
            }
        } else {
            logger.info("NO SAVE NEEDED: No documents were linked")
        }

        logger.info("=== LINK COMPLETE: \(linkedCount) documents linked to template ===")
        return linkedCount
    }

    // MARK: - Helpers

    /// Finds an instance that matches the given due date within tolerance.
    private func findMatchingInstance(
        for dueDate: Date,
        in instances: [RecurringInstance],
        toleranceDays: Int
    ) -> RecurringInstance? {
        let calendar = Calendar.current
        let tolerance = TimeInterval(toleranceDays * 24 * 60 * 60)

        return instances.first { instance in
            let timeDifference = abs(instance.effectiveDueDate.timeIntervalSince(dueDate))
            return timeDifference <= tolerance
        }
    }
}
