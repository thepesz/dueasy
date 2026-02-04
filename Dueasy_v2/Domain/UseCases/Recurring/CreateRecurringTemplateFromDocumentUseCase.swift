import Foundation
import os.log

/// Use case for creating a recurring template from a document (manual path).
/// Called when user enables the "Recurring Payment" toggle after scanning.
///
/// Flow (Standard):
/// 1. Generate vendor fingerprint if not present
/// 2. Classify document category
/// 3. Create RecurringTemplate
/// 4. Generate instances for next N months
/// 5. Match current document to the current month instance
///
/// Flow (Fuzzy Match - variable amounts):
/// 1. Check for existing templates from same vendor with similar amounts
/// 2. If 30-50% different, return candidates for user confirmation
/// 3. User chooses: "Same Service" -> link to existing, "Different Service" -> create new
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

    // MARK: - Fuzzy Match Detection

    /// Checks if the input should trigger fuzzy match confirmation.
    /// Call this BEFORE creating a template when user enables recurring.
    /// - Parameters:
    ///   - input: The fuzzy match check input containing vendor name, NIP, and amount
    /// - Returns: FuzzyMatchResult indicating next steps
    @MainActor
    func checkForFuzzyMatch(input: FuzzyMatchCheckInput) async throws -> FuzzyMatchResult {
        logger.info("[FuzzyMatch] Checking for fuzzy match for vendor")

        guard !input.vendorName.isEmpty else {
            logger.warning("[FuzzyMatch] Input has no vendor name - returning noExistingTemplates")
            return .noExistingTemplates
        }

        return try await templateService.checkForFuzzyMatch(
            vendorName: input.vendorName,
            nip: input.nip,
            amount: input.amount
        )
    }

    /// Legacy method for checking fuzzy match with a document.
    /// Prefer using `checkForFuzzyMatch(input:)` to avoid creating temporary documents.
    /// - Parameters:
    ///   - document: The source document
    /// - Returns: FuzzyMatchResult indicating next steps
    @MainActor
    func checkForFuzzyMatch(document: FinanceDocument) async throws -> FuzzyMatchResult {
        let input = FuzzyMatchCheckInput(
            vendorName: document.title,
            nip: document.vendorNIP,
            amount: document.amount
        )
        return try await checkForFuzzyMatch(input: input)
    }

    /// Links a document to an existing template (used when user confirms "Same Service").
    /// This is the "merge" path - no new template is created.
    /// - Parameters:
    ///   - document: The source document
    ///   - templateId: The template ID to link to
    ///   - reminderOffsets: Reminder offsets in days before due date
    ///   - toleranceDays: Tolerance for matching due dates
    ///   - monthsAhead: Number of months ahead to generate instances
    /// - Returns: The existing template and any newly generated instances
    @MainActor
    func linkToExistingTemplate(
        document: FinanceDocument,
        templateId: UUID,
        reminderOffsets: [Int]? = nil,
        toleranceDays: Int? = nil,
        monthsAhead: Int? = nil
    ) async throws -> CreateRecurringResult {
        logger.info("[FuzzyMatch] Linking document \(document.id) to existing template \(templateId)")

        guard let template = try await templateService.fetchTemplate(byId: templateId) else {
            throw RecurringError.templateNotFound
        }

        // Update the template's amount range to include this new amount
        try await templateService.updateTemplateAmountRangeForMerge(template, with: document.amount)

        // Generate vendor fingerprint for the document to match the template
        let fingerprintResult = fingerprintService.generateFingerprintWithMetadata(
            vendorName: document.title,
            nip: document.vendorNIP,
            amount: document.amount
        )
        document.vendorFingerprint = fingerprintResult.fingerprint

        // Classify document category if unknown
        if document.documentCategory == .unknown {
            let classification = classifierService.classify(
                vendorName: document.title,
                ocrText: nil,
                amount: document.amount
            )
            document.documentCategory = classification.category
        }

        // Generate instances if needed (may already exist for this month)
        let effectiveMonthsAhead = monthsAhead ?? Self.defaultMonthsAhead
        let instances = try await schedulerService.generateInstances(
            for: template,
            monthsAhead: effectiveMonthsAhead,
            includeHistorical: true
        )

        logger.info("[FuzzyMatch] Generated/retrieved \(instances.count) recurring instances")

        // Match current document to the appropriate instance
        if let dueDate = document.dueDate {
            let periodKey = dateService.periodKey(for: dueDate)
            if let matchingInstance = instances.first(where: { $0.periodKey == periodKey }) {
                try await matcherService.attachDocument(
                    document,
                    to: matchingInstance,
                    template: template
                )
                logger.info("[FuzzyMatch] Attached document to instance: \(periodKey)")
            } else {
                logger.warning("[FuzzyMatch] No matching instance found for period: \(periodKey)")
            }
        }

        return CreateRecurringResult(
            template: template,
            instances: instances,
            categoryWarning: nil
        )
    }

    // MARK: - Standard Template Creation

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

        // Step 1: Generate vendor fingerprint with amount bucket
        // CRITICAL: Always regenerate fingerprint with amount to ensure proper bucketing
        // This separates "Santander Credit Card (500 PLN)" from "Santander Loan (1200 PLN)"
        let fingerprintResult = fingerprintService.generateFingerprintWithMetadata(
            vendorName: document.title,
            nip: document.vendorNIP,
            amount: document.amount
        )
        document.vendorFingerprint = fingerprintResult.fingerprint
        logger.info("Generated vendor fingerprint with amount bucket: \(fingerprintResult.amountBucket ?? "none")")

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
