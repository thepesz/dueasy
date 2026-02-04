import Foundation
import SwiftData
import os.log

/// Service for managing recurring payment templates.
///
/// Handles creation, updates, and queries for `RecurringTemplate` entities.
/// Templates represent recurring payment patterns (e.g., monthly electricity bill)
/// and are used to generate and match recurring instances.
///
/// **Thread Safety:** All methods require `@MainActor` due to SwiftData constraints.
protocol RecurringTemplateServiceProtocol: Sendable {
    /// Creates a new recurring template from a document.
    ///
    /// Generates a vendor fingerprint (with amount bucket) and creates the template.
    /// The document's due date determines the expected due day of month.
    ///
    /// - Parameters:
    ///   - document: The source document. Must have a non-empty title and due date.
    ///   - reminderOffsets: Reminder offsets in days before due date (e.g., [7, 1, 0]).
    ///   - toleranceDays: Tolerance for matching due dates (+/- days).
    ///   - creationSource: How the template was created (`.manual` or `.autoDetection`).
    /// - Returns: The created `RecurringTemplate`.
    /// - Throws: `RecurringError.missingDueDate` if document has no due date.
    /// - Throws: `RecurringError.templateAlreadyExists` if a template with the same fingerprint exists.
    func createTemplate(
        from document: FinanceDocument,
        reminderOffsets: [Int],
        toleranceDays: Int,
        creationSource: TemplateCreationSource
    ) async throws -> RecurringTemplate

    /// Creates a template from an auto-detection candidate.
    ///
    /// Used when the system detects a recurring pattern from multiple documents
    /// and the user confirms it should become a template.
    ///
    /// - Parameters:
    ///   - candidate: The recurring candidate from detection.
    ///   - reminderOffsets: Reminder offsets in days before due date.
    ///   - toleranceDays: Tolerance for matching due dates.
    /// - Returns: The created `RecurringTemplate`.
    /// - Throws: `RecurringError.templateAlreadyExists` if a template with the same fingerprint exists.
    func createTemplate(
        from candidate: RecurringCandidate,
        reminderOffsets: [Int],
        toleranceDays: Int
    ) async throws -> RecurringTemplate

    /// Fetches a template by vendor fingerprint.
    ///
    /// - Parameter vendorFingerprint: The full vendor fingerprint (includes amount bucket).
    /// - Returns: The template if found, `nil` otherwise.
    /// - Throws: SwiftData fetch errors.
    func fetchTemplate(byVendorFingerprint vendorFingerprint: String) async throws -> RecurringTemplate?

    /// Fetches a template by ID.
    ///
    /// - Parameter id: The template's UUID.
    /// - Returns: The template if found, `nil` otherwise.
    /// - Throws: SwiftData fetch errors.
    func fetchTemplate(byId id: UUID) async throws -> RecurringTemplate?

    /// Fetches all active templates.
    ///
    /// Active templates are those where `isActive == true`.
    ///
    /// - Returns: Array of active templates, sorted by vendor display name.
    /// - Throws: SwiftData fetch errors.
    func fetchActiveTemplates() async throws -> [RecurringTemplate]

    /// Fetches all templates (active and paused).
    ///
    /// - Returns: Array of all templates, sorted by vendor display name.
    /// - Throws: SwiftData fetch errors.
    func fetchAllTemplates() async throws -> [RecurringTemplate]

    /// Updates a template with new settings.
    ///
    /// Only provided parameters are updated; pass `nil` to leave unchanged.
    ///
    /// - Parameters:
    ///   - template: The template to update.
    ///   - reminderOffsets: New reminder offsets, or `nil` to keep current.
    ///   - toleranceDays: New tolerance days, or `nil` to keep current.
    ///   - isActive: New active status, or `nil` to keep current.
    /// - Throws: SwiftData save errors.
    func updateTemplate(
        _ template: RecurringTemplate,
        reminderOffsets: [Int]?,
        toleranceDays: Int?,
        isActive: Bool?
    ) async throws

    /// Updates template amount range based on a matched document.
    ///
    /// Expands the template's min/max amount range to include the new amount.
    /// This allows the template to learn the variance in recurring payment amounts.
    ///
    /// - Parameters:
    ///   - template: The template to update.
    ///   - amount: The amount from the matched document.
    /// - Throws: SwiftData save errors.
    func updateAmountRange(_ template: RecurringTemplate, with amount: Decimal) async throws

    /// Deletes a template and its instances.
    ///
    /// Also clears recurring linkage from all documents associated with the template.
    ///
    /// - Parameter template: The template to delete.
    /// - Throws: SwiftData errors.
    func deleteTemplate(_ template: RecurringTemplate) async throws

    /// Checks if a template exists for a vendor fingerprint.
    ///
    /// - Parameter vendorFingerprint: The full vendor fingerprint.
    /// - Returns: `true` if a template with this fingerprint exists.
    /// - Throws: SwiftData fetch errors.
    func templateExists(forVendorFingerprint vendorFingerprint: String) async throws -> Bool

    /// Fetches all templates from the same vendor (using vendor-only fingerprint).
    ///
    /// Useful for finding "related" templates like multiple services from the same vendor
    /// (e.g., Santander Credit Card and Santander Loan).
    ///
    /// - Parameter vendorOnlyFingerprint: The vendor-only fingerprint (without amount bucket).
    /// - Returns: Array of templates from the same vendor.
    /// - Throws: SwiftData fetch errors.
    func fetchTemplates(byVendorOnlyFingerprint vendorOnlyFingerprint: String) async throws -> [RecurringTemplate]

    /// Finds template that best matches a document based on fingerprint and amount.
    ///
    /// This handles the case where a vendor has multiple templates (e.g., Santander Credit Card vs Loan).
    /// First tries exact fingerprint match, then falls back to finding the template whose amount
    /// range best contains the document amount.
    ///
    /// - Parameters:
    ///   - vendorName: The vendor name from the document.
    ///   - nip: Optional NIP (Polish tax ID).
    ///   - amount: The document amount.
    /// - Returns: Best matching template, or `nil` if no suitable match found.
    /// - Throws: SwiftData fetch errors.
    func findBestMatchingTemplate(vendorName: String, nip: String?, amount: Decimal) async throws -> RecurringTemplate?

    /// Checks for fuzzy match candidates when creating a recurring template.
    ///
    /// This enables the "variable amount" detection flow where similar amounts from the same vendor
    /// might be the same recurring payment with price changes.
    ///
    /// **Result Categories:**
    /// - `.noExistingTemplates`: No templates from this vendor exist.
    /// - `.exactMatch`: Template with exact fingerprint already exists.
    /// - `.autoMatch`: Amount is within 30% of existing template (auto-link).
    /// - `.needsConfirmation`: Amount is 30-50% different (user must decide).
    /// - `.autoCreateNew`: Amount is >50% different (create new template).
    ///
    /// - Parameters:
    ///   - vendorName: The vendor name from the document.
    ///   - nip: Optional NIP (Polish tax ID).
    ///   - amount: The document amount.
    /// - Returns: `FuzzyMatchResult` indicating the recommended action.
    /// - Throws: SwiftData fetch errors.
    func checkForFuzzyMatch(vendorName: String, nip: String?, amount: Decimal) async throws -> FuzzyMatchResult

    /// Updates template amount range after user confirms "Same Service" fuzzy match.
    ///
    /// Expands the template's amount range to include the new amount, allowing
    /// the template to handle variable amounts from the same recurring payment.
    ///
    /// - Parameters:
    ///   - template: The template to update.
    ///   - amount: The new document's amount.
    /// - Throws: SwiftData save errors.
    func updateTemplateAmountRangeForMerge(_ template: RecurringTemplate, with amount: Decimal) async throws
}

/// Default implementation of RecurringTemplateService.
///
/// Note: `@MainActor` is required because SwiftData's `ModelContext` is not Sendable
/// and must be accessed from the main actor. This constraint is inherent to SwiftData's
/// design and cannot be avoided while using ModelContext directly.
@MainActor
final class RecurringTemplateService: RecurringTemplateServiceProtocol {

    private let modelContext: ModelContext
    private let fingerprintService: VendorFingerprintServiceProtocol
    private let logger = Logger(subsystem: "com.dueasy.app", category: "RecurringTemplate")

    init(modelContext: ModelContext, fingerprintService: VendorFingerprintServiceProtocol = VendorFingerprintService()) {
        self.modelContext = modelContext
        self.fingerprintService = fingerprintService
    }

    // MARK: - Template Creation

    func createTemplate(
        from document: FinanceDocument,
        reminderOffsets: [Int],
        toleranceDays: Int,
        creationSource: TemplateCreationSource
    ) async throws -> RecurringTemplate {
        guard let dueDate = document.dueDate else {
            throw RecurringError.missingDueDate
        }

        // Generate fingerprint with amount bucket for better discrimination
        // This separates "Santander Credit Card (500 PLN)" from "Santander Loan (1200 PLN)"
        let fingerprintResult = fingerprintService.generateFingerprintWithMetadata(
            vendorName: document.title,
            nip: document.vendorNIP,
            amount: document.amount
        )

        let vendorFingerprint = fingerprintResult.fingerprint

        // Check if template already exists for this exact fingerprint (vendor + amount bucket)
        if try await templateExists(forVendorFingerprint: vendorFingerprint) {
            logger.warning("[TemplateService] Template creation blocked: fingerprint \(vendorFingerprint.prefix(16))... already exists")
            throw RecurringError.templateAlreadyExists
        }

        // Also update the document's fingerprint to use the new amount-aware version
        document.vendorFingerprint = vendorFingerprint

        let calendar = Calendar.current
        let dueDayOfMonth = calendar.component(.day, from: dueDate)

        // Generate short name by normalizing the vendor name (removes business suffixes)
        let shortName = fingerprintService.normalizeVendorName(document.title)

        let template = RecurringTemplate(
            vendorFingerprint: vendorFingerprint,
            vendorOnlyFingerprint: fingerprintResult.vendorOnlyFingerprint,
            amountBucket: fingerprintResult.amountBucket,
            vendorDisplayName: document.title,
            vendorShortName: shortName,
            documentCategory: document.documentCategory,
            dueDayOfMonth: dueDayOfMonth,
            toleranceDays: toleranceDays,
            reminderOffsetsDays: reminderOffsets,
            amountMin: document.amount,
            amountMax: document.amount,
            currency: document.currency,
            iban: document.bankAccountNumber,
            isActive: true,
            creationSource: creationSource
        )

        modelContext.insert(template)
        try modelContext.save()

        // PRIVACY: Don't log vendor name (document.title)
        logger.info("Created recurring template: id=\(template.id), source=\(creationSource.rawValue), bucket=\(fingerprintResult.amountBucket ?? "none")")

        return template
    }

    func createTemplate(
        from candidate: RecurringCandidate,
        reminderOffsets: [Int],
        toleranceDays: Int
    ) async throws -> RecurringTemplate {
        // Generate fingerprint with amount bucket using average amount from candidate
        let fingerprintResult = fingerprintService.generateFingerprintWithMetadata(
            vendorName: candidate.vendorDisplayName,
            nip: nil, // Candidates don't have NIP stored separately
            amount: candidate.averageAmount
        )

        let vendorFingerprint = fingerprintResult.fingerprint

        // Check if template already exists for this exact fingerprint
        if try await templateExists(forVendorFingerprint: vendorFingerprint) {
            logger.warning("[TemplateService] Template creation from candidate blocked: fingerprint \(vendorFingerprint.prefix(16))... already exists")
            throw RecurringError.templateAlreadyExists
        }

        // Generate short name by normalizing the vendor name (removes business suffixes)
        let shortName = fingerprintService.normalizeVendorName(candidate.vendorDisplayName)

        let template = RecurringTemplate(
            vendorFingerprint: vendorFingerprint,
            vendorOnlyFingerprint: fingerprintResult.vendorOnlyFingerprint,
            amountBucket: fingerprintResult.amountBucket,
            vendorDisplayName: candidate.vendorDisplayName,
            vendorShortName: shortName,
            documentCategory: candidate.documentCategory,
            dueDayOfMonth: candidate.dominantDueDayOfMonth ?? 15,
            toleranceDays: toleranceDays,
            reminderOffsetsDays: reminderOffsets,
            amountMin: candidate.minAmount,
            amountMax: candidate.maxAmount,
            currency: candidate.currency,
            iban: candidate.stableIBAN,
            isActive: true,
            creationSource: .autoDetection
        )

        modelContext.insert(template)

        // Mark candidate as accepted
        candidate.accept(templateId: template.id)

        try modelContext.save()

        // PRIVACY: Don't log vendor name
        logger.info("Created recurring template from candidate: id=\(template.id), bucket=\(fingerprintResult.amountBucket ?? "none")")

        return template
    }

    // MARK: - Template Queries

    func fetchTemplate(byVendorFingerprint vendorFingerprint: String) async throws -> RecurringTemplate? {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.vendorFingerprint == vendorFingerprint }
        )
        let templates = try modelContext.fetch(descriptor)
        return templates.first
    }

    func fetchTemplate(byId id: UUID) async throws -> RecurringTemplate? {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.id == id }
        )
        let templates = try modelContext.fetch(descriptor)
        return templates.first
    }

    func fetchActiveTemplates() async throws -> [RecurringTemplate] {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.isActive == true },
            sortBy: [SortDescriptor(\.vendorDisplayName)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllTemplates() async throws -> [RecurringTemplate] {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            sortBy: [SortDescriptor(\.vendorDisplayName)]
        )
        let results = try modelContext.fetch(descriptor)

        // Enhanced logging for debugging "7 of 9" issue
        logger.info("[TemplateService] fetchAllTemplates: found \(results.count) templates in database")
        let activeCount = results.filter { $0.isActive }.count
        let pausedCount = results.filter { !$0.isActive }.count
        logger.info("[TemplateService] Active: \(activeCount), Paused: \(pausedCount)")

        return results
    }

    func templateExists(forVendorFingerprint vendorFingerprint: String) async throws -> Bool {
        let template = try await fetchTemplate(byVendorFingerprint: vendorFingerprint)
        return template != nil
    }

    func fetchTemplates(byVendorOnlyFingerprint vendorOnlyFingerprint: String) async throws -> [RecurringTemplate] {
        let descriptor = FetchDescriptor<RecurringTemplate>(
            predicate: #Predicate<RecurringTemplate> { $0.vendorOnlyFingerprint == vendorOnlyFingerprint },
            sortBy: [SortDescriptor(\.vendorDisplayName)]
        )
        return try modelContext.fetch(descriptor)
    }

    func findBestMatchingTemplate(vendorName: String, nip: String?, amount: Decimal) async throws -> RecurringTemplate? {
        // First, try exact fingerprint match (vendor + NIP + amount bucket)
        let exactFingerprint = fingerprintService.generateFingerprint(vendorName: vendorName, nip: nip, amount: amount)
        if let exactMatch = try await fetchTemplate(byVendorFingerprint: exactFingerprint) {
            logger.debug("Found exact fingerprint match for vendor")
            return exactMatch
        }

        // If no exact match, look for vendor-only matches and find the one with closest amount range
        let vendorOnlyFingerprint = fingerprintService.generateVendorOnlyFingerprint(vendorName: vendorName, nip: nip)
        let vendorTemplates = try await fetchTemplates(byVendorOnlyFingerprint: vendorOnlyFingerprint)

        guard !vendorTemplates.isEmpty else {
            // No templates from this vendor at all
            return nil
        }

        // Find template with amount range closest to the document amount
        // Prefer templates where the amount falls within their learned range
        var bestMatch: RecurringTemplate?
        var bestScore = Double.infinity

        for template in vendorTemplates {
            guard template.isActive else { continue }

            // Check if amount is within template's range
            if template.isAmountWithinRange(amount) {
                // If amount is in range, prefer templates with narrower ranges (more specific)
                let rangeSize: Double
                if let min = template.amountMin, let max = template.amountMax {
                    rangeSize = NSDecimalNumber(decimal: max - min).doubleValue
                } else {
                    rangeSize = 0 // No range learned yet
                }

                if rangeSize < bestScore {
                    bestScore = rangeSize
                    bestMatch = template
                }
            }
        }

        if let match = bestMatch {
            logger.debug("Found amount-range match for vendor (multiple templates exist)")
            return match
        }

        // If no template with matching amount range, return nil (document might need new template)
        logger.debug("No matching template found - vendor has \(vendorTemplates.count) template(s) but none match amount")
        return nil
    }

    // MARK: - Template Updates

    func updateTemplate(
        _ template: RecurringTemplate,
        reminderOffsets: [Int]?,
        toleranceDays: Int?,
        isActive: Bool?
    ) async throws {
        if let offsets = reminderOffsets {
            template.reminderOffsetsDays = offsets
        }
        if let tolerance = toleranceDays {
            template.toleranceDays = tolerance
        }
        if let active = isActive {
            template.isActive = active
        }
        template.markUpdated()

        try modelContext.save()
        // PRIVACY: Don't log vendor name
        logger.info("Updated recurring template: id=\(template.id)")
    }

    func updateAmountRange(_ template: RecurringTemplate, with amount: Decimal) async throws {
        template.updateAmountRange(with: amount)
        try modelContext.save()
    }

    // MARK: - Fuzzy Match Detection

    func checkForFuzzyMatch(vendorName: String, nip: String?, amount: Decimal) async throws -> FuzzyMatchResult {
        // Step 1: Check for exact fingerprint match (vendor + NIP + amount bucket)
        let exactFingerprint = fingerprintService.generateFingerprint(vendorName: vendorName, nip: nip, amount: amount)
        if let exactMatch = try await fetchTemplate(byVendorFingerprint: exactFingerprint) {
            logger.info("[FuzzyMatch] Exact fingerprint match found - template already exists")
            return .exactMatch(templateId: exactMatch.id)
        }

        // Step 2: Get vendor-only fingerprint to find all templates from this vendor
        let vendorOnlyFingerprint = fingerprintService.generateVendorOnlyFingerprint(vendorName: vendorName, nip: nip)
        let vendorTemplates = try await fetchTemplates(byVendorOnlyFingerprint: vendorOnlyFingerprint)

        // No templates from this vendor - safe to create new
        guard !vendorTemplates.isEmpty else {
            logger.info("[FuzzyMatch] No existing templates from this vendor - will create new")
            return .noExistingTemplates
        }

        // Step 3: Calculate percent difference for each template and categorize
        var fuzzyZoneCandidates: [FuzzyMatchCandidate] = []
        var bestAutoMatch: (template: RecurringTemplate, percentDiff: Double)?

        for template in vendorTemplates where template.isActive {
            let percentDiff = FuzzyMatchCalculator.calculatePercentDifference(
                newAmount: amount,
                existingMin: template.amountMin,
                existingMax: template.amountMax
            )

            let category = FuzzyMatchCalculator.categorize(percentDifference: percentDiff)

            switch category {
            case .autoMatch:
                // Track the best (lowest percent diff) auto-match
                if bestAutoMatch == nil || percentDiff < bestAutoMatch!.percentDiff {
                    bestAutoMatch = (template, percentDiff)
                }
                logger.debug("[FuzzyMatch] Template \(template.id): \(Int(percentDiff * 100))% diff -> auto-match candidate")

            case .fuzzyZone:
                // Add to fuzzy zone candidates for user confirmation
                let candidate = FuzzyMatchCandidate(
                    template: template,
                    newAmount: amount,
                    percentDifference: percentDiff
                )
                fuzzyZoneCandidates.append(candidate)
                logger.debug("[FuzzyMatch] Template \(template.id): \(Int(percentDiff * 100))% diff -> fuzzy zone (needs confirmation)")

            case .autoCreateNew:
                // This template is too different, ignore it
                logger.debug("[FuzzyMatch] Template \(template.id): \(Int(percentDiff * 100))% diff -> too different, ignoring")
            }
        }

        // Step 4: Return appropriate result

        // If we have an auto-match, use it
        if let autoMatch = bestAutoMatch {
            logger.info("[FuzzyMatch] Auto-matching to template \(autoMatch.template.id) with \(Int(autoMatch.percentDiff * 100))% difference")
            return .autoMatch(templateId: autoMatch.template.id, percentDifference: autoMatch.percentDiff)
        }

        // If we have fuzzy zone candidates, user needs to decide
        if !fuzzyZoneCandidates.isEmpty {
            // Sort by percent difference (closest match first)
            let sortedCandidates = fuzzyZoneCandidates.sorted { $0.percentDifference < $1.percentDifference }
            logger.info("[FuzzyMatch] Found \(sortedCandidates.count) fuzzy match candidates - needs user confirmation")
            return .needsConfirmation(candidates: sortedCandidates)
        }

        // All templates were too different - auto-create new
        logger.info("[FuzzyMatch] All existing templates are too different (>50%) - will create new")
        return .autoCreateNew
    }

    func updateTemplateAmountRangeForMerge(_ template: RecurringTemplate, with amount: Decimal) async throws {
        template.updateAmountRange(with: amount)
        try modelContext.save()
        logger.info("[FuzzyMatch] Updated template \(template.id) amount range to include \(amount)")
    }

    // MARK: - Template Deletion

    func deleteTemplate(_ template: RecurringTemplate) async throws {
        let templateId = template.id

        // Fetch all instances for this template
        let instanceDescriptor = FetchDescriptor<RecurringInstance>(
            predicate: #Predicate<RecurringInstance> { $0.templateId == templateId }
        )
        let instances = try modelContext.fetch(instanceDescriptor)

        logger.info("Deleting template \(templateId): \(instances.count) instances will be removed")

        // CRITICAL FIX: Clear linkage from all documents linked to these instances
        for instance in instances {
            if let documentId = instance.matchedDocumentId {
                let docDescriptor = FetchDescriptor<FinanceDocument>(
                    predicate: #Predicate<FinanceDocument> { $0.id == documentId }
                )
                if let document = try modelContext.fetch(docDescriptor).first {
                    logger.debug("Clearing recurring linkage from document \(documentId)")
                    document.recurringInstanceId = nil
                    document.recurringTemplateId = nil
                    document.markUpdated()
                }
            }
            modelContext.delete(instance)
        }

        // Also clear linkage from documents linked to the template but not to a specific instance
        // This can happen if instance creation failed after template linkage
        let docsWithTemplateDescriptor = FetchDescriptor<FinanceDocument>(
            predicate: #Predicate<FinanceDocument> { $0.recurringTemplateId == templateId }
        )
        let documentsWithTemplate = try modelContext.fetch(docsWithTemplateDescriptor)
        for document in documentsWithTemplate {
            logger.debug("Clearing orphaned template linkage from document \(document.id)")
            document.recurringInstanceId = nil
            document.recurringTemplateId = nil
            document.markUpdated()
        }

        // Delete the template
        modelContext.delete(template)
        try modelContext.save()

        // PRIVACY: Don't log vendor name
        logger.info("Deleted recurring template (id=\(templateId)), \(instances.count) instances, and cleared \(documentsWithTemplate.count) document linkages")
    }
}

// MARK: - Recurring Errors

/// Errors specific to recurring payment operations
enum RecurringError: Error, LocalizedError {
    case missingVendorFingerprint
    case missingDueDate
    case templateAlreadyExists
    case templateNotFound
    case instanceNotFound
    case matchingFailed(reason: String)
    case schedulingFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .missingVendorFingerprint:
            return "Vendor fingerprint is required to create a recurring template"
        case .missingDueDate:
            return "Due date is required to create a recurring template"
        case .templateAlreadyExists:
            return "A recurring template already exists for this vendor"
        case .templateNotFound:
            return "Recurring template not found"
        case .instanceNotFound:
            return "Recurring instance not found"
        case .matchingFailed(let reason):
            return "Failed to match document to recurring instance: \(reason)"
        case .schedulingFailed(let reason):
            return "Failed to schedule recurring instances: \(reason)"
        }
    }
}
