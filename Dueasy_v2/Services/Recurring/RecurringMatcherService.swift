import Foundation
import SwiftData
import os.log

/// Service for matching scanned documents to recurring payment instances.
/// Implements the matching rules:
/// - Must have same vendorFingerprint
/// - Must have dueDate within expectedDueDate +/- toleranceDays
/// - Boost for IBAN match and amount within range
/// - Hard reject for fuel/retail/receipt categories without dueDate
protocol RecurringMatcherServiceProtocol: Sendable {
    /// Attempts to match a document to a recurring template and instance.
    /// - Parameter document: The document to match
    /// - Returns: Match result if found, nil otherwise
    func match(document: FinanceDocument) async throws -> RecurringMatchResult?

    /// Attaches a document to a matched instance.
    /// - Parameters:
    ///   - document: The document to attach
    ///   - instance: The instance to attach to
    ///   - template: The parent template
    func attachDocument(
        _ document: FinanceDocument,
        to instance: RecurringInstance,
        template: RecurringTemplate
    ) async throws

    /// Validates whether a document is eligible for recurring matching.
    /// - Parameter document: The document to validate
    /// - Returns: Validation result with reason if rejected
    func validateForMatching(document: FinanceDocument, templateExists: Bool) -> MatchValidationResult
}

/// Result of a recurring match operation
struct RecurringMatchResult {
    let template: RecurringTemplate
    let instance: RecurringInstance
    let matchScore: Double
    let matchReason: String
}

/// Result of match validation
struct MatchValidationResult {
    let isEligible: Bool
    let reason: String?

    static let eligible = MatchValidationResult(isEligible: true, reason: nil)

    static func rejected(reason: String) -> MatchValidationResult {
        MatchValidationResult(isEligible: false, reason: reason)
    }
}

/// Default implementation of RecurringMatcherService.
///
/// Note: `@MainActor` is required because SwiftData's `ModelContext` is not Sendable
/// and must be accessed from the main actor. This constraint is inherent to SwiftData's
/// design and cannot be avoided while using ModelContext directly.
@MainActor
final class RecurringMatcherService: RecurringMatcherServiceProtocol {

    private let modelContext: ModelContext
    private let templateService: RecurringTemplateServiceProtocol
    private let schedulerService: RecurringSchedulerServiceProtocol
    private let dateService: RecurringDateServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringMatcher")

    init(
        modelContext: ModelContext,
        templateService: RecurringTemplateServiceProtocol,
        schedulerService: RecurringSchedulerServiceProtocol,
        dateService: RecurringDateServiceProtocol = RecurringDateService()
    ) {
        self.modelContext = modelContext
        self.templateService = templateService
        self.schedulerService = schedulerService
        self.dateService = dateService
    }

    // MARK: - Matching

    func match(document: FinanceDocument) async throws -> RecurringMatchResult? {
        // CRITICAL FIX: Check basic requirements first (fingerprint, due date)
        guard let vendorFingerprint = document.vendorFingerprint, !vendorFingerprint.isEmpty else {
            logger.debug("Document missing vendor fingerprint")
            return nil
        }

        guard let dueDate = document.dueDate else {
            logger.debug("Document missing due date")
            return nil
        }

        // CRITICAL FIX: Find template using amount-aware fingerprint matching
        // The document's vendorFingerprint already includes amount bucket (generated in UseCase)
        //
        // Matching Strategy:
        // 1. Try exact fingerprint match (vendor + NIP + amount bucket)
        // 2. If no exact match, use findBestMatchingTemplate to find closest amount range
        //
        // This separates "Santander Credit Card (500 PLN)" from "Santander Loan (1200 PLN)"
        var template = try await templateService.fetchTemplate(byVendorFingerprint: vendorFingerprint)

        // If no exact match, try to find best matching template by vendor + amount range
        if template == nil {
            template = try await templateService.findBestMatchingTemplate(
                vendorName: document.title,
                nip: document.vendorNIP,
                amount: document.amount
            )
            if template != nil {
                logger.debug("Found template via amount-range matching (no exact fingerprint match)")
            }
        }

        guard let template = template else {
            logger.debug("No recurring template found for vendor fingerprint or amount range")
            return nil
        }

        // CRITICAL FIX: Now validate category restrictions
        // If template exists, skip category check (user explicitly marked as recurring)
        // This allows matching retail/fuel categories when user manually creates template
        let validation = validateForMatching(document: document, templateExists: true)
        guard validation.isEligible else {
            logger.info("Document not eligible for recurring match: \(validation.reason ?? "unknown")")
            return nil
        }

        // Template must be active
        guard template.isActive else {
            logger.debug("Template is paused, skipping match")
            return nil
        }

        // Find the matching instance for this due date
        let periodKey = dateService.periodKey(for: dueDate)

        // CRITICAL FIX: Handle race condition where concurrent documents for the same
        // vendor/period can both trigger instance generation, creating duplicates.
        // We use a pattern of: fetch -> generate if missing -> re-fetch to handle races.
        if let existingInstance = try await schedulerService.fetchInstance(templateId: template.id, periodKey: periodKey) {
            logger.info("MATCH: Found existing instance for period \(periodKey)")
            return try await tryMatch(document: document, template: template, instance: existingInstance, dueDate: dueDate)
        }

        // No instance for this period - generate instances (may race with concurrent call)
        logger.info("MATCH: No instance for period \(periodKey), generating...")
        let generatedInstances = try await schedulerService.generateInstances(for: template, monthsAhead: 3, includeHistorical: false)

        // CRITICAL FIX: Re-fetch to handle concurrent generation race condition
        // Another thread may have created the instance while we were generating.
        // The re-fetch ensures we use the existing instance rather than creating duplicates.
        if let finalInstance = try await schedulerService.fetchInstance(templateId: template.id, periodKey: periodKey) {
            logger.info("MATCH: Found instance after generation (may have been created concurrently)")
            return try await tryMatch(document: document, template: template, instance: finalInstance, dueDate: dueDate)
        }

        // If still not found after re-fetch, check our generated instances
        // This handles the case where generation succeeded but fetch has race timing issues
        guard let newInstance = generatedInstances.first(where: { $0.periodKey == periodKey }) else {
            logger.warning("MATCH: Failed to generate or find instance for period \(periodKey)")
            return nil
        }

        logger.info("MATCH: Using newly generated instance from generation batch")
        return try await tryMatch(document: document, template: template, instance: newInstance, dueDate: dueDate)
    }

    private func tryMatch(
        document: FinanceDocument,
        template: RecurringTemplate,
        instance: RecurringInstance,
        dueDate: Date
    ) async throws -> RecurringMatchResult? {
        // Instance must be in expected or matched state (allow re-matching)
        guard instance.status == .expected || instance.status == .matched else {
            logger.debug("Instance already in terminal state: \(instance.status.rawValue)")
            return nil
        }

        // Check due date tolerance - use fixed timezone calendar for consistency
        let daysDifference = dateService.daysBetween(
            from: instance.expectedDueDate,
            to: dueDate
        )

        guard abs(daysDifference) <= template.toleranceDays else {
            logger.debug("Due date outside tolerance: \(daysDifference) days (tolerance: \(template.toleranceDays))")
            return nil
        }

        // Calculate match score
        var score = 0.7 // Base score for vendor + date match
        var reasons: [String] = ["Vendor match", "Date within tolerance"]

        // Boost for IBAN match
        if let templateIBAN = template.iban,
           let documentIBAN = document.bankAccountNumber,
           !templateIBAN.isEmpty && templateIBAN == documentIBAN {
            score += 0.15
            reasons.append("IBAN match")
        }

        // Boost for amount within range
        if template.isAmountWithinRange(document.amount) {
            score += 0.1
            reasons.append("Amount in range")
        }

        // Small penalty for date difference
        if daysDifference != 0 {
            score -= Double(abs(daysDifference)) * 0.02
        }

        logger.info("Matched document to recurring instance: \(instance.periodKey) (score: \(score))")

        return RecurringMatchResult(
            template: template,
            instance: instance,
            matchScore: min(score, 1.0),
            matchReason: reasons.joined(separator: ", ")
        )
    }

    // MARK: - Attachment

    func attachDocument(
        _ document: FinanceDocument,
        to instance: RecurringInstance,
        template: RecurringTemplate
    ) async throws {
        // Update instance with document data
        instance.matchDocument(
            documentId: document.id,
            dueDate: document.dueDate ?? instance.expectedDueDate,
            amount: document.amount,
            invoiceNumber: document.documentNumber
        )

        // Update document with recurring references
        document.recurringTemplateId = template.id
        document.recurringInstanceId = instance.id

        // Update template statistics
        template.incrementMatchedCount()
        try await templateService.updateAmountRange(template, with: document.amount)

        // Update notifications with final due date
        try await schedulerService.updateNotificationsAfterMatch(
            for: instance,
            template: template,
            vendorName: template.vendorDisplayName
        )

        try modelContext.save()

        logger.info("Attached document \(document.id) to recurring instance \(instance.periodKey)")
    }

    // MARK: - Validation

    func validateForMatching(document: FinanceDocument, templateExists: Bool = false) -> MatchValidationResult {
        // Must have vendor fingerprint
        guard let fingerprint = document.vendorFingerprint, !fingerprint.isEmpty else {
            return .rejected(reason: "Missing vendor fingerprint")
        }

        // Must have due date
        guard document.dueDate != nil else {
            return .rejected(reason: "Missing due date")
        }

        // ARCHITECTURAL DECISION: Category restrictions removed.
        // User knows their invoices best. If they create a recurring template,
        // we match it regardless of category. Keyword-based classification is
        // too brittle (misses vendors like LANTECH) and will be replaced with
        // manual category selection in future UI.
        //
        // Classification still runs for UI display, but NEVER blocks matching.

        return .eligible
    }
}
