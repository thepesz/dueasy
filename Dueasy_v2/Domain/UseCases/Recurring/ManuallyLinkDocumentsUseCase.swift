import Foundation
import os.log

/// TEMPORARY USE CASE: Manually link existing documents to existing templates.
/// This is needed to fix documents that were created before the linking fix was deployed.
///
/// Can be called from settings or triggered manually to retroactively link documents.
final class ManuallyLinkDocumentsUseCase: @unchecked Sendable {

    private let documentRepository: DocumentRepositoryProtocol
    private let schedulerService: RecurringSchedulerServiceProtocol
    private let templateService: RecurringTemplateServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "ManualLinkDocuments")

    init(
        documentRepository: DocumentRepositoryProtocol,
        schedulerService: RecurringSchedulerServiceProtocol,
        templateService: RecurringTemplateServiceProtocol
    ) {
        self.documentRepository = documentRepository
        self.schedulerService = schedulerService
        self.templateService = templateService
    }

    /// Manually link all unlinked documents to existing templates.
    /// - Returns: Number of documents successfully linked
    @MainActor
    func execute() async throws -> Int {
        logger.debug("Starting manual document linking")

        // Get all templates
        let templates = try await templateService.fetchAllTemplates()
        logger.info("Found \(templates.count) templates")

        var totalLinked = 0

        for template in templates {
            // PRIVACY: Don't log vendor name
            logger.info("Processing template: id=\(template.id)")

            // Find documents for this vendor
            let documents = try await documentRepository.fetch(byVendorFingerprint: template.vendorFingerprint)
            logger.info("  Found \(documents.count) documents for vendor")

            // Get instances for this template
            let instances = try await schedulerService.fetchInstances(forTemplateId: template.id)
            logger.info("  Found \(instances.count) instances")

            // Link unlinked documents
            for document in documents {
                // Skip already linked documents
                if document.recurringInstanceId != nil {
                    logger.debug("  Document \(document.id) already linked, skipping")
                    continue
                }

                guard let documentDueDate = document.dueDate else {
                    logger.debug("  Document \(document.id) has no due date, skipping")
                    continue
                }

                // Find matching instance
                if let matchingInstance = findMatchingInstance(
                    for: documentDueDate,
                    in: instances,
                    toleranceDays: template.toleranceDays
                ) {
                    // Link document to instance
                    document.recurringInstanceId = matchingInstance.id
                    document.recurringTemplateId = template.id
                    document.markUpdated()

                    // Update instance
                    matchingInstance.matchDocument(
                        documentId: document.id,
                        dueDate: documentDueDate,
                        amount: document.amount,
                        invoiceNumber: document.documentNumber
                    )

                    if document.status == .paid {
                        matchingInstance.markAsPaid()
                    }

                    logger.debug("Linked document \(document.id) to instance \(matchingInstance.id)")
                    totalLinked += 1
                }
            }
        }

        // CRITICAL: Save all changes
        if totalLinked > 0 {
            logger.info("SAVING: Persisting \(totalLinked) linked documents to database...")
            try await documentRepository.save()
            logger.info("SAVE SUCCESS: All document linkages persisted")
        }

        logger.info("Manual linking complete: \(totalLinked) documents linked")
        return totalLinked
    }

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
