import Foundation
import os.log

/// Use case for creating a recurring template from a document (manual path).
/// Called when user enables the "Recurring Payment" toggle after scanning.
///
/// Flow:
/// 1. Generate vendor fingerprint if not present
/// 2. Classify document category
/// 3. Create RecurringTemplate
/// 4. Generate instances for next N months
/// 5. Match current document to the current month instance
final class CreateRecurringTemplateFromDocumentUseCase: @unchecked Sendable {

    private let templateService: RecurringTemplateServiceProtocol
    private let schedulerService: RecurringSchedulerServiceProtocol
    private let matcherService: RecurringMatcherServiceProtocol
    private let fingerprintService: VendorFingerprintServiceProtocol
    private let classifierService: DocumentClassifierServiceProtocol
    private let dateService: RecurringDateServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "CreateRecurringTemplate")

    /// Default reminder offsets
    static let defaultReminderOffsets = [7, 1, 0]

    /// Default tolerance days
    static let defaultToleranceDays = 3

    /// Default months ahead to generate
    static let defaultMonthsAhead = 3

    init(
        templateService: RecurringTemplateServiceProtocol,
        schedulerService: RecurringSchedulerServiceProtocol,
        matcherService: RecurringMatcherServiceProtocol,
        fingerprintService: VendorFingerprintServiceProtocol,
        classifierService: DocumentClassifierServiceProtocol,
        dateService: RecurringDateServiceProtocol = RecurringDateService()
    ) {
        self.templateService = templateService
        self.schedulerService = schedulerService
        self.matcherService = matcherService
        self.fingerprintService = fingerprintService
        self.classifierService = classifierService
        self.dateService = dateService
    }

    /// Creates a recurring template from a document.
    /// - Parameters:
    ///   - document: The source document (must have vendor name and due date)
    ///   - reminderOffsets: Reminder offsets in days before due date (default: [7, 1, 0])
    ///   - toleranceDays: Tolerance for matching due dates (default: 3)
    ///   - monthsAhead: Number of months ahead to generate instances (default: 3)
    /// - Returns: The created template and generated instances
    @MainActor
    func execute(
        document: FinanceDocument,
        reminderOffsets: [Int]? = nil,
        toleranceDays: Int? = nil,
        monthsAhead: Int? = nil
    ) async throws -> CreateRecurringResult {
        logger.info("Creating recurring template from document: \(document.id)")

        // Validate document has required fields
        guard document.dueDate != nil else {
            throw RecurringError.missingDueDate
        }

        guard !document.title.isEmpty else {
            throw RecurringError.missingVendorFingerprint
        }

        // Step 1: Generate vendor fingerprint if not present
        if document.vendorFingerprint == nil || document.vendorFingerprint?.isEmpty == true {
            let fingerprint = fingerprintService.generateFingerprint(
                vendorName: document.title,
                nip: document.vendorNIP
            )
            document.vendorFingerprint = fingerprint
            logger.info("Generated vendor fingerprint for document")
        }

        // Step 2: Classify document category if unknown
        if document.documentCategory == .unknown {
            let classification = classifierService.classify(
                vendorName: document.title,
                ocrText: nil,
                amount: document.amount
            )
            document.documentCategory = classification.category
            logger.info("Classified document as: \(classification.category.rawValue)")
        }

        // Step 3: Create template
        let effectiveReminderOffsets = reminderOffsets ?? Self.defaultReminderOffsets
        let effectiveToleranceDays = toleranceDays ?? Self.defaultToleranceDays

        let template = try await templateService.createTemplate(
            from: document,
            reminderOffsets: effectiveReminderOffsets,
            toleranceDays: effectiveToleranceDays,
            creationSource: .manual
        )

        logger.info("Created recurring template: \(template.id)")

        // Step 4: Generate instances for next N months
        // includeHistorical: true to handle templates created from historical documents
        let effectiveMonthsAhead = monthsAhead ?? Self.defaultMonthsAhead
        let instances = try await schedulerService.generateInstances(
            for: template,
            monthsAhead: effectiveMonthsAhead,
            includeHistorical: true
        )

        logger.info("Generated \(instances.count) recurring instances")

        // Step 5: Match current document to the appropriate instance
        let periodKey = dateService.periodKey(for: document.dueDate!)
        if let matchingInstance = instances.first(where: { $0.periodKey == periodKey }) {
            try await matcherService.attachDocument(
                document,
                to: matchingInstance,
                template: template
            )
            logger.info("Attached document to instance: \(periodKey)")
        }

        // ARCHITECTURAL DECISION: Category warnings removed.
        // User knows their invoices best. No warnings for category.
        // Manual category selection will be added in future UI.
        let categoryWarning: CategoryWarning? = nil

        return CreateRecurringResult(
            template: template,
            instances: instances,
            categoryWarning: categoryWarning
        )
    }
}

/// Result of creating a recurring template
struct CreateRecurringResult {
    /// The created template
    let template: RecurringTemplate

    /// Generated instances for future months
    let instances: [RecurringInstance]

    /// Warning about the document category (if applicable)
    let categoryWarning: CategoryWarning?
}

/// Warning about document category for recurring
enum CategoryWarning {
    /// Document is fuel, retail, grocery, or receipt - unusual for recurring
    case fuelRetailCategory

    /// Document category is unknown
    case unknownCategory

    var message: String {
        switch self {
        case .fuelRetailCategory:
            return L10n.Recurring.warningFuelRetail.localized
        case .unknownCategory:
            return L10n.Recurring.warningNoPattern.localized
        }
    }
}
